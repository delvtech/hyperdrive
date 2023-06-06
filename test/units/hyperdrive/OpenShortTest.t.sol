// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { VmSafe } from "forge-std/Vm.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";
import { console } from "forge-std/console.sol";

contract OpenShortTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using HyperdriveUtils for IHyperdrive;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_open_short_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to short zero bonds. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.openShort(0, type(uint256).max, bob, true);
    }

    function test_open_short_failure_pause() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to add zero base as liquidity. This should fail.
        vm.stopPrank();
        pause(true);
        vm.startPrank(bob);
        vm.expectRevert(Errors.Paused.selector);
        hyperdrive.openShort(0, type(uint256).max, bob, true);
        vm.stopPrank();
        pause(false);
    }

    function test_open_short_failure_extreme_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to short an extreme amount of bonds. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = hyperdrive.getPoolInfo().shareReserves;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        vm.expectRevert(Errors.FixedPointMath_SubOverflow.selector);
        hyperdrive.openShort(baseAmount * 2, type(uint256).max, bob, true);
    }

    function test_open_short() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Short a small amount of bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, uint256 baseAmount) = openShort(bob, bondAmount);

        // Verify the open short updates occurred correctly.
        verifyOpenShort(
            poolInfoBefore,
            contribution,
            baseAmount,
            bondAmount,
            maturityTime,
            apr
        );
    }

    function test_open_short_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Short a small amount of bonds.
        uint256 bondAmount = .1e18;
        (uint256 maturityTime, uint256 baseAmount) = openShort(bob, bondAmount);

        // Verify the open short updates occurred correctly.
        verifyOpenShort(
            poolInfoBefore,
            contribution,
            baseAmount,
            bondAmount,
            maturityTime,
            apr
        );
    }

    function test_ShortAvoidsDrainingBufferReserves() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open up a large long to init buffer reserves
        uint256 bondAmount = hyperdrive.calculateMaxLong();
        openLong(bob, bondAmount);

        // Initialize a large long to eath through the buffer of capital
        uint256 overlyLargeShort = 500608690308195651844553347;

        // Open the long.
        vm.stopPrank();
        vm.startPrank(bob);
        baseToken.mint(overlyLargeShort);
        baseToken.approve(address(hyperdrive), overlyLargeShort);

        vm.expectRevert(Errors.BaseBufferExceedsShareReserves.selector);
        hyperdrive.openShort(overlyLargeShort, type(uint256).max, bob, true);
    }

    function test_RevertsWithNegativeInterestRate() public {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        vm.stopPrank();
        vm.startPrank(bob);

        uint256 bondAmount = (hyperdrive.calculateMaxShort() * 90) / 100;
        openShort(bob, bondAmount);

        uint256 longAmount = (hyperdrive.calculateMaxLong() * 50) / 100;
        openLong(bob, longAmount);

        //vm.expectRevert(Errors.NegativeInterest.selector);

        uint256 baseAmount = (hyperdrive.calculateMaxShort() * 100) / 100;
        openShort(bob, baseAmount);
        //I think we could trigger this with big short, open long, and short?
    }

    function verifyOpenShort(
        IHyperdrive.PoolInfo memory poolInfoBefore,
        uint256 contribution,
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 maturityTime,
        uint256 apr
    ) internal {
        uint256 checkpointTime = maturityTime - POSITION_DURATION;

        // Ensure that one `OpenShort` event was emitted with the correct
        // arguments.
        {
            VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
                OpenShort.selector
            );
            assertEq(logs.length, 1);
            VmSafe.Log memory log = logs[0];
            assertEq(address(uint160(uint256(log.topics[1]))), bob);
            (
                uint256 eventAssetId,
                uint256 eventMaturityTime,
                uint256 eventBaseAmount,
                uint256 eventBondAmount
            ) = abi.decode(log.data, (uint256, uint256, uint256, uint256));
            assertEq(
                eventAssetId,
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime)
            );
            assertEq(eventMaturityTime, maturityTime);
            assertEq(eventBaseAmount, baseAmount);
            assertEq(eventBondAmount, bondAmount);
        }

        // Verify that Hyperdrive received the max loss and that Bob received
        // the short tokens.
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            contribution + baseAmount
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

        // Verify that the short didn't receive an APR higher than the pool's
        // APR.
        uint256 baseProceeds = bondAmount - baseAmount;
        {
            uint256 realizedApr = HyperdriveUtils.calculateAPRFromRealizedPrice(
                baseProceeds,
                bondAmount,
                FixedPointMath.ONE_18
            );
            assertLt(apr, realizedApr);
        }

        // Verify that the reserves were updated correctly.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        {
            IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
                checkpointTime
            );
            assertEq(
                poolInfoAfter.shareReserves,
                poolInfoBefore.shareReserves -
                    baseProceeds.divDown(poolInfoBefore.sharePrice)
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
                maturityTime * 1e18,
                1
            );
            assertEq(poolInfoAfter.shortBaseVolume, baseProceeds);
            assertEq(checkpoint.shortBaseVolume, baseProceeds);
        }

        // Ensure that the bond reserves were updated to have the correct APR.
        // Due to the way that the flat part of the trade is applied, the bond
        // reserve updates may not exactly correspond to the amount of bonds
        // transferred; however, the pool's APR should be identical to the APR
        // that the bond amount transfer implies.
        assertApproxEqAbs(
            HyperdriveUtils.calculateAPRFromReserves(hyperdrive),
            HyperdriveMath.calculateAPRFromReserves(
                poolInfoAfter.shareReserves,
                poolInfoBefore.bondReserves + bondAmount,
                INITIAL_SHARE_PRICE,
                POSITION_DURATION,
                hyperdrive.getPoolConfig().timeStretch
            ),
            5
        );
    }
}
