// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { stdError } from "forge-std/StdError.sol";
import { Test } from "forge-std/Test.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import { ERC20Mintable } from "test/mocks/ERC20Mintable.sol";
import { MockHyperdrive } from "test/mocks/MockHyperdrive.sol";

contract HyperdriveTest is Test {
    using FixedPointMath for uint256;

    address alice = address(uint160(uint256(keccak256("alice"))));
    address bob = address(uint160(uint256(keccak256("bob"))));

    ERC20Mintable baseToken;
    MockHyperdrive hyperdrive;

    function setUp() public {
        vm.startPrank(alice);

        // Instantiate the base token.
        baseToken = new ERC20Mintable();

        // Instantiate Hyperdrive.
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            22.186877016851916266e18
        );
        hyperdrive = new MockHyperdrive(
            baseToken,
            FixedPointMath.ONE_18,
            365,
            1 days,
            timeStretch
        );

        // Advance time so that Hyperdrive can look back more than a position
        // duration.
        vm.warp(365 days * 3);
    }

    /// initialize ///

    function initialize(
        address lp,
        uint256 apr,
        uint256 contribution
    ) internal {
        vm.stopPrank();
        vm.startPrank(lp);

        // Initialize the pool.
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.initialize(contribution, apr);
    }

    function test_initialize_failure() external {
        uint256 apr = 0.5e18;
        uint256 contribution = 1000.0e18;

        // Initialize the pool with Alice.
        initialize(alice, apr, contribution);

        // Attempt to initialize the pool a second time. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        vm.expectRevert(Errors.PoolAlreadyInitialized.selector);
        hyperdrive.initialize(contribution, apr);
    }

    // TODO: We need a test that verifies that the quoted APR is the same as the
    // realized APR of making a small trade on the pool. This should be part of
    // the open long testing.
    //
    // TODO: This should ultimately be a fuzz test that fuzzes over the initial
    // share price, the APR, the contribution, the position duration, and other
    // parameters that can have an impact on the pool's APR.
    function test_initialize_success() external {
        uint256 apr = 0.05e18;
        uint256 contribution = 1000e18;

        // Initialize the pool with Alice.
        initialize(alice, apr, contribution);

        // Ensure that the pool's APR is approximately equal to the target APR.
        uint256 poolApr = HyperdriveMath.calculateAPRFromReserves(
            hyperdrive.shareReserves(),
            hyperdrive.bondReserves(),
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            hyperdrive.initialSharePrice(),
            hyperdrive.positionDuration(),
            hyperdrive.timeStretch()
        );
        assertApproxEqAbs(poolApr, apr, 1); // 17 decimals of precision

        // Ensure that Alice's base balance has been depleted and that Alice
        // received some LP tokens.
        assertEq(baseToken.balanceOf(alice), 0);
        assertEq(baseToken.balanceOf(address(hyperdrive)), contribution);
        assertEq(
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            contribution + hyperdrive.bondReserves()
        );
    }

    /// addLiquidity ///

    function test_addLiquidity_failure_ZeroAmount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to purchase bonds with zero base. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.addLiquidity(0, 0, bob);
    }

    /// openLong ///

    function test_open_long_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to purchase bonds with zero base. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.openLong(0, 0, bob);
    }

    function test_open_long_extreme_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to purchase more bonds than exist. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = hyperdrive.bondReserves();
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.openLong(baseAmount, 0, bob);
    }

    function test_open_long() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Purchase a small amount of bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = 10e18;

        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);

        // Verify the base transfers.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            contribution + baseAmount
        );

        // Verify that Bob received an acceptable amount of bonds. Since the
        // base amount is very low relative to the pool's liquidity, the implied
        // APR should be approximately equal to the pool's APR.
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        uint256 bondAmount = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bob
        );
        uint256 realizedApr = calculateAPRFromRealizedPrice(
            baseAmount,
            bondAmount,
            maturityTime - block.timestamp,
            365 days
        );

        // Verify that opening a long doesn't make the APR go up
        assertGt(apr, realizedApr);
        
        // Verify that the reserves were updated correctly.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves +
                baseAmount.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(
            poolInfoAfter.bondReserves,
            poolInfoBefore.bondReserves - bondAmount
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding + bondAmount
        );
        assertApproxEqAbs(
            poolInfoAfter.longAverageMaturityTime,
            maturityTime,
            1
        );
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
    }

    function test_open_long_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Purchase a small amount of bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = .01e18;
        
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);

        // Verify the base transfers.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            contribution + baseAmount
        );

        // Verify that Bob received an acceptable amount of bonds. Since the
        // base amount is very low relative to the pool's liquidity, the implied
        // APR should be approximately equal to the pool's APR.
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        uint256 bondAmount = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bob
        );
        uint256 realizedApr = calculateAPRFromRealizedPrice(
            baseAmount,
            bondAmount,
            maturityTime - block.timestamp,
            365 days
        );

        // Verify that opening a long doesn't make the APR go up
        assertGt(apr, realizedApr);
        
        // Verify that the reserves were updated correctly.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves +
                baseAmount.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(
            poolInfoAfter.bondReserves,
            poolInfoBefore.bondReserves - bondAmount
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding + bondAmount
        );
        assertApproxEqAbs(
            poolInfoAfter.longAverageMaturityTime,
            maturityTime,
            1
        );
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
    }

    /// Close Long ///

    function test_close_long_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = 10e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);

        // Attempt to close zero longs. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        hyperdrive.closeLong(maturityTime, 0, 0, bob);
    }

    function test_close_long_invalid_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = 10e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);

        // Attempt to close too many longs. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        uint256 bondAmount = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bob
        );
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.closeLong(maturityTime, bondAmount + 1, 0, bob);
    }

    function test_close_long_invalid_timestamp() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = 10e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);

        // Attempt to use a timestamp greater than the maximum range.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.InvalidTimestamp.selector);
        hyperdrive.closeLong(uint256(type(uint248).max) + 1, 1, 0, bob);
    }

    function test_close_long_immediately() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = 10e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Immediately close the bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        uint256 bondAmount = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bob
        );
        hyperdrive.closeLong(maturityTime, bondAmount, 0, bob);

        // Verify that all of Bob's bonds were burned and that he has
        // approximately as much base as he started with.
        uint256 baseProceeds = baseToken.balanceOf(bob);
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                bob
            ),
            0
        );
        // Verify that bob doesn't end up with more than he started with
        assertGe(baseAmount, baseProceeds);

        // Verify that the reserves were updated correctly. Since this trade
        // happens at the beginning of the term, the bond reserves should be
        // increased by the full amount.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves -
                baseProceeds.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(
            poolInfoAfter.bondReserves,
            poolInfoBefore.bondReserves + bondAmount
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding - bondAmount
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
    }

    function test_close_long_immediately_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = .01e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Immediately close the bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        uint256 bondAmount = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bob
        );
        hyperdrive.closeLong(maturityTime, bondAmount, 0, bob);

        // Verify that all of Bob's bonds were burned and that he has
        // approximately as much base as he started with.
        uint256 baseProceeds = baseToken.balanceOf(bob);
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                bob
            ),
            0
        );
        // Verify that bob doesn't end up with more than he started with
        assertGe(baseAmount, baseProceeds);

        // Verify that the reserves were updated correctly. Since this trade
        // happens at the beginning of the term, the bond reserves should be
        // increased by the full amount.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves -
                baseProceeds.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(
            poolInfoAfter.bondReserves,
            poolInfoBefore.bondReserves + bondAmount
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding - bondAmount
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
    }

    // TODO: Clean up these tests.
    function test_close_long_redeem() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = 10e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // The term passes.
        vm.warp(block.timestamp + 365 days);

        // Redeem the bonds
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bob
        );

        hyperdrive.closeLong(maturityTime, bondAmount, 0, bob);

        // Verify that all of Bob's bonds were burned and that he has
        // approximately as much base as he started with.
        uint256 baseProceeds = baseToken.balanceOf(bob);
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                bob
            ),
            0
        );
        assertEq(baseProceeds, bondAmount);

        // Verify that the reserves were updated correctly. Since this trade
        // is a redemption, there should be no changes to the bond reserves.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves -
                bondAmount.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding - bondAmount
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
    }

    /// Open Short ///

    function test_open_short_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to short zero bonds. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.openShort(0, type(uint256).max, bob);
    }

    function test_open_short_extreme_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to short an extreme amount of bonds. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = hyperdrive.shareReserves();
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        vm.expectRevert(Errors.FixedPointMath_SubOverflow.selector);
        hyperdrive.openShort(baseAmount * 2, type(uint256).max, bob);
    }

    function test_open_short() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the short.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Short a small amount of bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = 10e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        hyperdrive.openShort(bondAmount, type(uint256).max, bob);

        // Verify that Hyperdrive received the max loss and that Bob received
        // the short tokens.
        uint256 maxLoss = bondAmount - baseToken.balanceOf(bob);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            contribution + maxLoss
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                bob
            ),
            bondAmount
        );

        // Verify that Bob's short has an acceptable fixed rate. Since the bond
        // amount is very low relative to the pool's liquidity, the implied APR
        // should be approximately equal to the pool's APR.
        uint256 baseAmount = bondAmount - maxLoss;
        uint256 realizedApr = calculateAPRFromRealizedPrice(
            baseAmount,
            bondAmount,
            maturityTime - block.timestamp,
            365 days
        );
        // TODO: This tolerance seems too high.
        assertApproxEqAbs(realizedApr, apr, 1e10);

        // Verify that the reserves were updated correctly.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves -
                baseAmount.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(
            poolInfoAfter.bondReserves,
            poolInfoBefore.bondReserves + bondAmount
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding + bondAmount
        );
        assertApproxEqAbs(
            poolInfoAfter.shortAverageMaturityTime,
            maturityTime,
            1
        );
    }

    /// Close Short ///

    function test_close_short_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short..
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = 10e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        hyperdrive.openShort(bondAmount, type(uint256).max, bob);

        // Attempt to close zero shorts. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        hyperdrive.closeShort(maturityTime, 0, 0, bob);
    }

    function test_close_short_invalid_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = 10e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        hyperdrive.openShort(bondAmount, type(uint256).max, bob);

        // Attempt to close too many shorts. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.closeShort(maturityTime, bondAmount + 1, 0, bob);
    }

    function test_close_short_invalid_timestamp() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = 10e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        hyperdrive.openShort(bondAmount, type(uint256).max, bob);

        // Attempt to use a timestamp greater than the maximum range.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.InvalidTimestamp.selector);
        hyperdrive.closeShort(uint256(type(uint248).max) + 1, 1, 0, bob);
    }

    function test_close_short_immediately() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = 10e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        hyperdrive.openShort(bondAmount, type(uint256).max, bob);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Immediately close the bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        hyperdrive.closeShort(maturityTime, bondAmount, 0, bob);

        // TODO: Bob receives more base than he started with. Fees should take
        // care of this, but this should be investigating nonetheless.
        //
        // Verify that all of Bob's bonds were burned and that he has
        // approximately as much base as he started with.
        uint256 baseAmount = baseToken.balanceOf(bob);
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                bob
            ),
            0
        );
        assertApproxEqAbs(baseAmount, bondAmount, 1e10);

        // Verify that the reserves were updated correctly. Since this trade
        // happens at the beginning of the term, the bond reserves should be
        // increased by the full amount.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertApproxEqAbs(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves +
                baseAmount.divDown(poolInfoBefore.sharePrice),
            1e18
        );
        assertEq(
            poolInfoAfter.bondReserves,
            poolInfoBefore.bondReserves - bondAmount
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding - bondAmount
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
    }

    // TODO: Clean up these tests.
    function test_close_short_redeem() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = 10e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        hyperdrive.openShort(bondAmount, type(uint256).max, bob);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // The term passes.
        vm.warp(block.timestamp + 365 days);

        // Get the base balance before closing the short.
        uint256 baseBalanceBefore = baseToken.balanceOf(bob);

        // Redeem the bonds
        vm.stopPrank();
        vm.startPrank(bob);
        hyperdrive.closeShort(maturityTime, bondAmount, 0, bob);

        // TODO: Investigate this more to see if there are any irregularities
        // like there are with the long redemption test.
        //
        // Verify that all of Bob's bonds were burned and that he has
        // approximately as much base as he started with.
        uint256 baseBalanceAfter = baseToken.balanceOf(bob);
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                bob
            ),
            0
        );
        assertApproxEqAbs(baseBalanceAfter, baseBalanceBefore, 1e10);

        // Verify that the reserves were updated correctly. Since this trade
        // is a redemption, there should be no changes to the bond reserves.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves +
                bondAmount.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding - bondAmount
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
    }

    /// Utils ///

    function calculateAPRFromRealizedPrice(
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 timeRemaining,
        uint256 positionDuration
    ) internal pure returns (uint256) {
        // apr = (dy - dx) / (dx * t)
        uint256 t = timeRemaining.divDown(positionDuration);
        return (bondAmount.sub(baseAmount)).divDown(baseAmount.mulDown(t));
    }

    struct PoolInfo {
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 lpTotalSupply;
        uint256 sharePrice;
        uint256 longsOutstanding;
        uint256 longAverageMaturityTime;
        uint256 shortsOutstanding;
        uint256 shortAverageMaturityTime;
    }

    function getPoolInfo() internal view returns (PoolInfo memory) {
        (
            uint256 shareReserves,
            uint256 bondReserves,
            uint256 lpTotalSupply,
            uint256 sharePrice,
            uint256 longsOutstanding,
            uint256 longAverageMaturityTime,
            uint256 shortsOutstanding,
            uint256 shortAverageMaturityTime
        ) = hyperdrive.getPoolInfo();
        return
            PoolInfo({
                shareReserves: shareReserves,
                bondReserves: bondReserves,
                lpTotalSupply: lpTotalSupply,
                sharePrice: sharePrice,
                longsOutstanding: longsOutstanding,
                longAverageMaturityTime: longAverageMaturityTime,
                shortsOutstanding: shortsOutstanding,
                shortAverageMaturityTime: shortAverageMaturityTime
            });
    }
}
