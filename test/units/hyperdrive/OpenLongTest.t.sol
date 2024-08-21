// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { SafeCast } from "../../../contracts/src/libraries/SafeCast.sol";
import { YieldSpaceMath } from "../../../contracts/src/libraries/YieldSpaceMath.sol";
import { MockHyperdrive, IMockHyperdrive } from "../../../contracts/test/MockHyperdrive.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract OpenLongTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using SafeCast for uint256;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_open_long_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to purchase bonds with zero base. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.MinimumTransactionAmount.selector);
        hyperdrive.openLong(
            0,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_long_failure_not_payable() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to open long. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openLong{ value: 1 }(
            1,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_long_failure_destination_zero_address() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to purchase bonds with zero base. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = 10e18;
        baseToken.mint(bob, basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        vm.expectRevert(IHyperdrive.RestrictedZeroAddress.selector);
        hyperdrive.openLong(
            basePaid,
            0,
            0,
            IHyperdrive.Options({
                destination: address(0),
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_long_failure_pause() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to add zero base as liquidity. This should fail.
        pause(true);
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.PoolIsPaused.selector);
        hyperdrive.openLong(
            0,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
        pause(false);
    }

    function test_open_long_failure_negative_interest(
        uint256 fixedRate,
        uint256 contribution
    ) external {
        // Initialize the pool. We use a relatively small fixed rate to ensure
        // that the maximum long is constrained by the price cap of 1 rather
        // than because of exceeding the long buffer.
        fixedRate = fixedRate.normalizeToRange(0.0001e18, 0.1e18);
        contribution = contribution.normalizeToRange(1_000e18, 500_000_000e18);
        initialize(alice, fixedRate, contribution);

        // Ensure that a long that is slightly larger than the max long will
        // fail the negative interest check.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = hyperdrive.calculateMaxLong() + 0.0001e18;
        baseToken.mint(bob, basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        vm.expectRevert(IHyperdrive.InsufficientLiquidity.selector);
        hyperdrive.openLong(
            basePaid,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that the max long results in spot price very close to 1 to
        // make sure that the negative interest failure was appropriate.
        openLong(bob, hyperdrive.calculateMaxLong());
        assertLe(hyperdrive.calculateSpotPrice(), 1e18);
        assertApproxEqAbs(hyperdrive.calculateSpotPrice(), 1e18, 1e6);
    }

    function test_open_long_failure_extreme_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to purchase more bonds than exist. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = hyperdrive.getPoolInfo().bondReserves;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        vm.expectRevert(IHyperdrive.InsufficientLiquidity.selector);
        hyperdrive.openLong(
            baseAmount,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_long_failure_minimum_vault_share_price() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to open a long when the share price is lower than the minimum
        // share price.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = 10e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        uint256 minVaultSharePrice = 2 *
            hyperdrive.getPoolInfo().vaultSharePrice;
        vm.expectRevert(IHyperdrive.MinimumSharePrice.selector);
        hyperdrive.openLong(
            baseAmount,
            0,
            minVaultSharePrice,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_long() external {
        uint256 apr = 0.05e18;

        // Initialize the pools with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Open a long.
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, baseAmount);

        // Verify that the open long updated the state correctly.
        verifyOpenLong(
            poolInfoBefore,
            contribution,
            baseAmount,
            bondAmount,
            maturityTime,
            apr
        );
    }

    function test_open_long_destination() external {
        uint256 apr = 0.05e18;

        // Initialize the pools with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a long and send the position to celine.
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(
            bob,
            baseAmount,
            DepositOverrides({
                asBase: true,
                destination: celine,
                depositAmount: baseAmount,
                minSharePrice: 0, // min vault share price of 0
                minSlippage: baseAmount, // min bond proceeds of baseAmount
                maxSlippage: type(uint256).max, // unused
                extraData: new bytes(0) // unused
            })
        );

        // Ensure that the correct event was emitted.
        verifyOpenLongEvent(celine, maturityTime, bondAmount, baseAmount);

        // Ensure that the position was sent to celine.
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                bob
            ),
            0
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                celine
            ),
            bondAmount
        );
    }

    function test_open_long_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Purchase a small amount of bonds.
        uint256 baseAmount = .01e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, baseAmount);

        // Verify that the open long updated the state correctly.
        verifyOpenLong(
            poolInfoBefore,
            contribution,
            baseAmount,
            bondAmount,
            maturityTime,
            apr
        );
    }

    function test_LongAvoidsDrainingBufferReserves() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Initialize a long and set large exposure to eat through capital
        uint256 longAmount = 1e18;
        MockHyperdrive(address(hyperdrive)).setLongExposure(
            contribution.toUint128()
        );

        // Open the long.
        vm.stopPrank();
        vm.startPrank(bob);
        baseToken.mint(longAmount);
        baseToken.approve(address(hyperdrive), longAmount);
        vm.expectRevert(IHyperdrive.InsufficientLiquidity.selector);
        hyperdrive.openLong(
            longAmount,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    // Tests an edge case in `updateWeightedAverage` where the function output
    // is not bounded by the average and the delta. This test ensures that this
    // never occurs by attempting to induce a wild variation in avgPrice, and
    // ensures that they remain relatively consistent.
    function testAvoidsDustAttack(uint256 contribution, uint256 apr) public {
        // Apr between 0.5e18 and 0.25e18
        apr = apr.normalizeToRange(0.05e18, 0.25e18);
        // Initialize the pool with a large amount of capital.
        contribution = contribution.normalizeToRange(
            100_000_000e6,
            500_000_000e6
        );

        // Deploy the pool with a minimum share reserves that is significantly
        // smaller than the contribution.
        IHyperdrive.PoolConfig memory config = testConfig(
            apr,
            POSITION_DURATION
        );
        config.minimumShareReserves = 1e6;
        config.minimumTransactionAmount = 1e6;
        deploy(deployer, config);

        initialize(alice, apr, contribution);

        advanceTime(POSITION_DURATION, int256(apr));

        openLong(bob, config.minimumTransactionAmount * 2);

        IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
        uint256 averageMaturityTimeBefore = info.longAverageMaturityTime;

        uint256 amt = contribution / 5;
        openLong(bob, amt);

        info = hyperdrive.getPoolInfo();
        uint256 averageMaturityTimeAfter = info.longAverageMaturityTime;
        assertApproxEqAbs(
            averageMaturityTimeBefore,
            averageMaturityTimeAfter,
            1e4
        );
    }

    function verifyOpenLong(
        IHyperdrive.PoolInfo memory poolInfoBefore,
        uint256 contribution,
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 maturityTime,
        uint256 apr
    ) internal {
        // Ensure that one `OpenLong` event was emitted with the correct
        // arguments.
        verifyOpenLongEvent(bob, maturityTime, bondAmount, baseAmount);

        // Verify that the open long updated the state correctly.
        _verifyOpenLong(
            bob,
            poolInfoBefore,
            contribution,
            baseAmount,
            bondAmount,
            maturityTime,
            apr
        );

        // Deploy and initialize a new pool with fees.
        // Curve fee is set to 10%.
        // Flat fee is set to 1%.
        deploy(alice, apr, 0.1e18, 0.01e18, 0, 0);
        initialize(alice, apr, contribution);

        // Open a long with fees.
        IHyperdrive.PoolInfo memory poolInfoBeforeWithFees = hyperdrive
            .getPoolInfo();
        (, uint256 bondAmountWithFees) = openLong(celine, baseAmount);

        _verifyOpenLong(
            celine,
            poolInfoBeforeWithFees,
            contribution,
            baseAmount,
            bondAmountWithFees,
            maturityTime,
            apr
        );

        // let's manually check that the fees are collected appropriately
        // curve fee = ((1 / p) - 1) * phi * c * d_z * t
        // p = 1 / (1 + r)
        // roughly ((1/.9523 - 1) * .1) * 10e18 * 1 = 5e16, or 10% of the 5% bond - base spread.
        uint256 p = (uint256(1 ether)).divDown(1 ether + 0.05 ether);
        uint256 phi = hyperdrive.getPoolConfig().fees.curve;
        uint256 curveFeeAmount = (uint256(1 ether).divDown(p) - 1 ether)
            .mulDown(phi)
            .mulDown(baseAmount);

        IHyperdrive.PoolInfo memory poolInfoAfterWithFees = hyperdrive
            .getPoolInfo();

        // bondAmount is from the hyperdrive without the curve fee
        assertApproxEqAbs(
            poolInfoAfterWithFees.longsOutstanding,
            poolInfoBeforeWithFees.longsOutstanding +
                bondAmount -
                curveFeeAmount,
            10
        );
    }

    function _verifyOpenLong(
        address user,
        IHyperdrive.PoolInfo memory poolInfoBefore,
        uint256 contribution,
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 maturityTime,
        uint256 apr
    ) internal view {
        // Verify that base was transferred from the trader to Hyperdrive.
        assertEq(baseToken.balanceOf(user), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            contribution + baseAmount
        );

        // Verify that the trader received the correct amount of bonds.
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                user
            ),
            bondAmount
        );

        // Verify that opening a long doesn't make the APR go up.
        uint256 realizedApr = HyperdriveUtils.calculateAPRFromRealizedPrice(
            baseAmount,
            bondAmount,
            ONE
        );
        assertGt(apr, realizedApr);

        // Ensure that the state changes to the share reserves were applied
        // correctly and that the other pieces of state were left untouched.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves +
                baseAmount.divDown(poolInfoBefore.vaultSharePrice)
        );
        assertEq(poolInfoAfter.vaultSharePrice, poolInfoBefore.vaultSharePrice);
        assertEq(poolInfoAfter.shareAdjustment, poolInfoBefore.shareAdjustment);
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertApproxEqAbs(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding + bondAmount,
            10
        );
        HyperdriveUtils.calculateSpotAPR(hyperdrive);

        // Ensure that the bond reserves were updated to have the correct APR.
        // Due to the way that the flat part of the trade is applied, the bond
        // reserve updates may not exactly correspond to the amount of bonds
        // transferred; however, the pool's APR should be identical to the APR
        // that the bond amount transfer implies.
        assertApproxEqAbs(
            HyperdriveUtils.calculateSpotAPR(hyperdrive),
            HyperdriveMath.calculateSpotAPR(
                HyperdriveMath.calculateEffectiveShareReserves(
                    poolInfoAfter.shareReserves,
                    poolInfoAfter.shareAdjustment
                ),
                poolInfoBefore.bondReserves - bondAmount,
                INITIAL_SHARE_PRICE,
                POSITION_DURATION,
                hyperdrive.getPoolConfig().timeStretch
            ),
            5
        );

        // TODO: This problem gets much worse as the baseAmount to open a long gets smaller.
        // Figure out a solution to this.
        assertApproxEqAbs(
            poolInfoAfter.longAverageMaturityTime,
            maturityTime * 1e18,
            1
        );
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
    }

    function verifyOpenLongEvent(
        address destination,
        uint256 maturityTime,
        uint256 bondAmount,
        uint256 baseAmount
    ) internal {
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            OpenLong.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(address(uint160(uint256(log.topics[1]))), destination);
        assertEq(
            uint256(log.topics[2]),
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime)
        );
        (
            uint256 eventMaturityTime,
            uint256 eventAmount,
            uint256 eventVaultSharePrice,
            bool eventAsBase,
            uint256 eventBondAmount
        ) = abi.decode(log.data, (uint256, uint256, uint256, bool, uint256));
        assertEq(eventMaturityTime, maturityTime);
        assertEq(eventAmount, baseAmount);
        assertEq(
            eventVaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice
        );
        assertEq(eventAsBase, true);
        assertEq(eventBondAmount, bondAmount);
    }
}
