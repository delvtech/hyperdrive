// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

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
            365 days,
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
        assertApproxEqAbs(poolApr, apr, 1e1); // 17 decimals of precision

        // Ensure that Alice's base balance has been depleted and that Alice
        // received some LP tokens.
        assertEq(baseToken.balanceOf(alice), 0);
        assertEq(baseToken.balanceOf(address(hyperdrive)), contribution);
        assertEq(
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            contribution + hyperdrive.bondReserves()
        );
    }

    /// openLong ///

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

    function test_open_long_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to purchase bonds with zero base. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.openLong(0);
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
        hyperdrive.openLong(baseAmount);
    }

    function test_open_long() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the values of the reserves before the purchase.
        (
            uint256 shareReservesBefore,
            uint256 bondReservesBefore,
            uint256 lpTotalSupplyBefore,
            uint256 sharePriceBefore,
            uint256 longsOutstandingBefore,
            uint256 longsMaturedBefore,
            uint256 shortsOutstandingBefore,
            uint256 shortsMaturedBefore
        ) = hyperdrive.getPoolInfo();

        // TODO: Small base amounts result in higher than quoted APRs. We should
        // first investigate the math to see if there are obvious simplifications
        // to be made, and then consider increasing the amount of precision in
        // used in our fixed rate format.
        //
        // Purchase a small amount of bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = 10e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount);

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
        // TODO: This tolerance seems too high.
        assertApproxEqAbs(realizedApr, apr, 1e10);

        // Verify that the reserves were updated correctly.
        (
            uint256 shareReservesAfter,
            uint256 bondReservesAfter,
            uint256 lpTotalSupplyAfter,
            uint256 sharePriceAfter,
            uint256 longsOutstandingAfter,
            uint256 longsMaturedAfter,
            uint256 shortsOutstandingAfter,
            uint256 shortsMaturedAfter
        ) = hyperdrive.getPoolInfo();
        assertEq(
            shareReservesAfter,
            shareReservesBefore + baseAmount.divDown(sharePriceBefore)
        );
        assertEq(bondReservesAfter, bondReservesBefore - bondAmount);
        assertEq(lpTotalSupplyAfter, lpTotalSupplyBefore);
        assertEq(sharePriceAfter, sharePriceBefore);
        assertEq(longsOutstandingAfter, longsOutstandingBefore + bondAmount);
        assertEq(longsMaturedAfter, longsMaturedBefore);
        assertEq(shortsOutstandingAfter, shortsOutstandingBefore);
        assertEq(shortsMaturedAfter, shortsMaturedBefore);
    }
}
