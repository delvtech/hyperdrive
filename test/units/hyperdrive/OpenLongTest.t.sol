// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract OpenLongTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using HyperdriveUtils for IHyperdrive;

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
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.openLong(0, 0, bob, true);
    }

    function test_open_long_failure_pause() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to add zero base as liquidity. This should fail.
        vm.stopPrank();
        pause(true);
        vm.startPrank(bob);
        vm.expectRevert(Errors.Paused.selector);
        hyperdrive.openLong(0, 0, bob, true);
        vm.stopPrank();
        pause(false);
    }

    function test_pauser_authorization_fail() external {
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        hyperdrive.setPauser(alice, true);
        vm.expectRevert(Errors.Unauthorized.selector);
        hyperdrive.pause(true);
        vm.stopPrank();
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
        vm.expectRevert(Errors.NegativeInterest.selector);
        hyperdrive.openLong(baseAmount, 0, bob, true);
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

        // Open up a large short to drain the buffer reserves.
        uint256 bondAmount = hyperdrive.calculateMaxShort();
        openShort(bob, bondAmount);

        // Initialize a large long to eath through the buffer of capital
        uint256 overlyLargeLonge = 976625406180945208462181452;

        // Open the long.
        vm.stopPrank();
        vm.startPrank(bob);
        baseToken.mint(overlyLargeLonge);
        baseToken.approve(address(hyperdrive), overlyLargeLonge);

        vm.expectRevert(Errors.BaseBufferExceedsShareReserves.selector);
        hyperdrive.openLong(overlyLargeLonge, 0, bob, true);
    }

    function testAvoidsDustAttack(uint256 contribution, uint256 apr) public {
        // Apr between 0.5e18 and 0.25e18
        // Contribution between 100e6 to 500 million e6
        // openLong value should be 1/5 of contribution, nornmalize range subrange
        apr = apr.normalizeToRange(0.05e18, 0.25e18);
        contribution = contribution.normalizeToRange(100_000_000e18, 500_000_000e18);

        // Initialize the pool with a large amount of capital.
        contribution = contribution.normalizeToRange(
            100_000_000e6,
            500_000_000e6
        );

        initialize(alice, apr, contribution);

        advanceTime(POSITION_DURATION, int256(apr));

        openLong(bob, 1 wei);

        IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
        uint256 sharePrice = info.sharePrice;

        uint256 amt = contribution / 5;
        openLong(bob, amt);

        uint256 longSharePrice = hyperdrive
            .getCheckpoint(hyperdrive.latestCheckpoint())
            .longSharePrice;

        assertApproxEqAbs(sharePrice, longSharePrice, 1e7);
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
        {
            VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
                OpenLong.selector
            );
            assertEq(logs.length, 1);
            VmSafe.Log memory log = logs[0];
            assertEq(address(uint160(uint256(log.topics[1]))), bob);
            assertEq(
                uint256(log.topics[2]),
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime)
            );
            (
                uint256 eventMaturityTime,
                uint256 eventBaseAmount,
                uint256 eventBondAmount
            ) = abi.decode(log.data, (uint256, uint256, uint256));
            assertEq(eventMaturityTime, maturityTime);
            assertEq(eventBaseAmount, baseAmount);
            assertEq(eventBondAmount, bondAmount);
        }

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
        deploy(alice, apr, 0.1e18, 0.1e18, 0);
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
    ) internal {
        uint256 checkpointTime = maturityTime - POSITION_DURATION;

        // Verify the base transfers.
        assertEq(baseToken.balanceOf(user), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            contribution + baseAmount
        );

        // Verify that opening a long doesn't make the APR go up.
        uint256 realizedApr = HyperdriveUtils.calculateAPRFromRealizedPrice(
            baseAmount,
            bondAmount,
            FixedPointMath.ONE_18
        );
        assertGt(apr, realizedApr);

        // Ensure that the state changes to the share reserves were applied
        // correctly and that the other pieces of state were left untouched.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves +
                baseAmount.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertApproxEqAbs(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding + bondAmount,
            10
        );

        // Ensure that the bond reserves were updated to have the correct APR.
        // Due to the way that the flat part of the trade is applied, the bond
        // reserve updates may not exactly correspond to the amount of bonds
        // transferred; however, the pool's APR should be identical to the APR
        // that the bond amount transfer implies.
        assertApproxEqAbs(
            HyperdriveUtils.calculateAPRFromReserves(hyperdrive),
            HyperdriveMath.calculateAPRFromReserves(
                poolInfoAfter.shareReserves,
                poolInfoBefore.bondReserves - bondAmount,
                INITIAL_SHARE_PRICE,
                POSITION_DURATION,
                hyperdrive.getPoolConfig().timeStretch
            ),
            5
        );

        // TODO: This problem gets much worse as the baseAmount to open a long gets smaller.
        // Figure out a solution to this.
        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
            checkpointTime
        );
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
        assertEq(poolInfoAfter.shortBaseVolume, 0);
        assertEq(checkpoint.shortBaseVolume, 0);
    }
}
