// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { MockHyperdrive, IMockHyperdrive } from "contracts/test/MockHyperdrive.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract IntraCheckpointNettingTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function test_netting_basic_example() external {
        uint256 initialSharePrice = 1e18;

        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, 0, 0, 0);
        uint256 contribution = 100e18;
        uint256 aliceLpShares = initialize(alice, apr, contribution);

        // open a short
        uint256 shortAmount = 10e18;
        (uint256 maturityTimeShort, ) = openShort(bob, shortAmount);

        // open a long
        uint256 basePaidLong = 9.5e18;
        (uint256 maturityTimeLong, uint256 bondAmountLong) = openLong(
            alice,
            basePaidLong
        );

        // open a short
        uint256 shortAmount2 = 5e18;
        (uint256 maturityTimeShort2, ) = openShort(bob, shortAmount2);

        // remove liquidity
        removeLiquidity(alice, aliceLpShares);

        // wait for the shorts to mature to close them
        advanceTimeWithCheckpoints(POSITION_DURATION, 0);

        // close the long.
        closeLong(alice, maturityTimeLong, bondAmountLong);

        // close the short
        closeShort(bob, maturityTimeShort2, shortAmount2);

        // close the short
        closeShort(bob, maturityTimeShort, shortAmount);

        // longExposure should be 0
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        assertApproxEqAbs(poolInfo.longExposure, 0, 1);

        // idle should be equal to shareReserves
        uint256 expectedShareReserves = MockHyperdrive(address(hyperdrive))
            .calculateIdleShareReserves(hyperdrive.getPoolInfo().sharePrice) +
            hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }

    // This test was designed to show that a netted long and short can be closed at
    // maturity even if all liquidity is removed. This test would fail before we added the logic:
    // - to properly zero out exposure on checkpoint boundaries
    // - payout the withdrawal pool only when the idle capital is
    //   worth more than the active LP supply
    function test_netting_long_short_close_at_maturity() external {
        uint256 initialSharePrice = 1e18;
        int256 variableInterest = 0;
        uint256 timeElapsed = 10220546; //~118 days between each trade
        uint256 tradeSize = 100e18;

        // initialize the market
        uint256 aliceLpShares = 0;
        {
            uint256 apr = 0.05e18;
            deploy(alice, apr, initialSharePrice, 0, 0, 0);
            uint256 contribution = 500_000_000e18;
            aliceLpShares = initialize(alice, apr, contribution);

            // fast forward time and accrue interest
            advanceTime(POSITION_DURATION, 0);
        }

        // open a long
        uint256 basePaidLong = tradeSize;
        (uint256 maturityTimeLong, uint256 bondAmountLong) = openLong(
            bob,
            basePaidLong
        );

        // fast forward time, create checkpoints and accrue interest
        advanceTimeWithCheckpoints(timeElapsed, variableInterest);

        // open a short for the same number of bonds as the existing long
        uint256 shortAmount = bondAmountLong;
        (uint256 maturityTimeShort, ) = openShort(bob, shortAmount);

        // open a long
        (uint256 maturityTimeLong2, ) = openLong(bob, basePaidLong);

        // fast forward time, create checkpoints and accrue interest
        advanceTimeWithCheckpoints(timeElapsed, variableInterest);

        // open a short for the same number of bonds as the existing long
        (uint256 maturityTimeShort2, ) = openShort(bob, shortAmount);

        // remove liquidity
        (, uint256 withdrawalShares) = removeLiquidity(alice, aliceLpShares);

        // wait for the positions to mature
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        while (
            poolInfo.shortsOutstanding > 0 || poolInfo.longsOutstanding > 0
        ) {
            advanceTimeWithCheckpoints(POSITION_DURATION, variableInterest);
            poolInfo = hyperdrive.getPoolInfo();
        }

        // close the short positions
        closeShort(bob, maturityTimeShort, shortAmount);

        // close the long positions
        closeLong(bob, maturityTimeLong, bondAmountLong);

        // close the short positions
        closeShort(bob, maturityTimeShort2, shortAmount);

        // close the long positions
        closeLong(bob, maturityTimeLong2, bondAmountLong);

        // longExposure should be 0
        poolInfo = hyperdrive.getPoolInfo();
        assertApproxEqAbs(poolInfo.longExposure, 0, 1);

        redeemWithdrawalShares(alice, withdrawalShares);
        // idle should be equal to shareReserves
        uint256 expectedShareReserves = MockHyperdrive(address(hyperdrive))
            .calculateIdleShareReserves(hyperdrive.getPoolInfo().sharePrice) +
            hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }

    function test_netting_mismatched_exposure_maturities() external {
        uint256 initialSharePrice = 1e18;
        int256 variableInterest = 0e18;
        uint256 timeElapsed = 10220546; //~118 days between each trade
        uint256 tradeSize = 100e18;

        // initialize the market
        uint256 aliceLpShares = 0;
        {
            uint256 apr = 0.05e18;
            deploy(alice, apr, initialSharePrice, 0, 0, 0);
            uint256 contribution = 500_000_000e18;
            aliceLpShares = initialize(alice, apr, contribution);

            // fast forward time and accrue interest
            advanceTime(POSITION_DURATION, 0);
        }

        // open a long
        uint256 basePaidLong = tradeSize;
        (uint256 maturityTimeLong, uint256 bondAmountLong) = openLong(
            bob,
            basePaidLong
        );

        // fast forward time, create checkpoints and accrue interest
        advanceTimeWithCheckpoints(timeElapsed, variableInterest);

        // open a short for the same number of bonds as the existing long
        uint256 shortAmount = bondAmountLong;
        (uint256 maturityTimeShort, ) = openShort(bob, shortAmount);

        // remove liquidity
        (, uint256 withdrawalShares) = removeLiquidity(alice, aliceLpShares);

        // wait for the positions to mature
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        while (
            poolInfo.shortsOutstanding > 0 || poolInfo.longsOutstanding > 0
        ) {
            advanceTimeWithCheckpoints(POSITION_DURATION, variableInterest);
            poolInfo = hyperdrive.getPoolInfo();
        }

        // close the short positions
        closeShort(bob, maturityTimeShort, shortAmount);

        // close the long positions
        closeLong(bob, maturityTimeLong, bondAmountLong);

        // longExposure should be 0
        poolInfo = hyperdrive.getPoolInfo();
        assertApproxEqAbs(poolInfo.longExposure, 0, 1);

        redeemWithdrawalShares(alice, withdrawalShares);
        // idle should be equal to shareReserves
        uint256 expectedShareReserves = MockHyperdrive(address(hyperdrive))
            .calculateIdleShareReserves(hyperdrive.getPoolInfo().sharePrice) +
            hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }

    function test_netting_longs_close_with_initial_share_price_gt_1() external {
        uint256 initialSharePrice = 1.017375020334083692e18;
        int256 variableInterest = 0.050000000000000000e18;
        uint256 timeElapsed = 4924801;
        uint256 tradeSize = 3810533.716355891982851995e18;
        uint256 numTrades = 1;
        open_close_long(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    function test_netting_longs_can_close_with_no_shorts() external {
        uint256 initialSharePrice = 1.000252541820033020e18;
        int256 variableInterest = 0.050000000000000000e18;
        uint256 timeElapsed = POSITION_DURATION / 2;
        uint256 tradeSize = 369599.308648593814273788e18;
        uint256 numTrades = 2;
        open_close_long(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    // This test demonstrates that you can open longs and shorts indefinitely until
    // the interest drops so low that positions can't be closed.
    function test_netting_extreme_negative_interest_time_elapsed() external {
        uint256 initialSharePrice = 1e18;
        int256 variableInterest = -0.1e18; // NOTE: This is the lowest interest rate that can be used
        uint256 timeElapsed = 10220546; //~118 days between each trade
        uint256 tradeSize = 100e18;
        uint256 numTrades = 2;

        // If you increase numTrades enough it will eventually fail due to sub underflow
        // caused by share price going so low that k-y is negative (on openShort)
        open_close_long_short_different_checkpoints(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    function test_netting_zero_interest_small_time_elapsed() external {
        uint256 initialSharePrice = 1e18;
        int256 variableInterest = 0e18;
        uint256 timeElapsed = CHECKPOINT_DURATION / 3;
        uint256 tradeSize = 100e18; //100_000_000 fails with sub underflow
        uint256 numTrades = 100;

        // If you increase trade size enough it will eventually fail due to sub underflow
        // caused by share price going so low that k-y is negative (on openShort)
        open_close_long_short_different_checkpoints(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    // This test shows that you can open/close long/shorts with extreme positive interest
    function test_netting_extreme_positive_interest_time_elapsed() external {
        uint256 initialSharePrice = 0.5e18;
        int256 variableInterest = 0.5e18;
        uint256 timeElapsed = 15275477; //176 days bewteen each trade
        uint256 tradeSize = 504168.031667365798150347e18;
        uint256 numTrades = 100;

        // If you increase numTrades enough it will eventually fail in openLong()
        // due to minOutput > bondProceeds where minOutput = baseAmount from openLong()
        open_close_long_short_different_checkpoints(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    // This test shows that you can open large long/shorts repeatedly then wait 10 years to close all the positions
    function test_large_long_large_short_many_wait_to_redeem() external {
        uint256 initialSharePrice = 1e18;
        int256 variableInterest = 1.05e18;
        uint256 timeElapsed = 3650 days; // 10 years
        uint256 tradeSize = 100_000_000e18;
        uint256 numTrades = 250;

        // You can keep increasing the numTrades until the test fails from
        // NegativeInterest on the openLong() spotPrice > 1 check
        open_close_long_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    /// forge-config: default.fuzz.runs = 1000
    function test_netting_fuzz(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) external {
        // Fuzz inputs Standard Range
        // initialSharePrice [0.5,5]
        // variableInterest [0,50]
        // timeElapsed [0,365]
        // numTrades [1,5]
        // tradeSize [1,50_000_000/numTrades] 10% of the TVL
        initialSharePrice = initialSharePrice.normalizeToRange(0.5e18, 5e18);
        variableInterest = variableInterest.normalizeToRange(0e18, .5e18);
        timeElapsed = timeElapsed.normalizeToRange(0, POSITION_DURATION);
        numTrades = tradeSize.normalizeToRange(1, 5);
        tradeSize = tradeSize.normalizeToRange(1e18, 50_000_000e18 / numTrades);
        open_close_long(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        open_close_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        open_close_long_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    function test_netting_open_close_long() external {
        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long is opened and immediately closed
        // - trade size is 1 million
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = 0 days;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long is opened and closed after 182.5 days
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION / 2;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long is opened and closed after POSITION_DURATION
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);
    }

    function open_close_long(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        // open a long
        uint256 maturityTimeLong = 0;
        uint256[] memory bondAmounts = new uint256[](numTrades);
        for (uint256 i = 0; i < numTrades; i++) {
            uint256 basePaidLong = tradeSize;
            uint256 bondAmount = 0;
            (maturityTimeLong, bondAmount) = openLong(bob, basePaidLong);
            bondAmounts[i] = bondAmount;
        }

        // fast forward time, create checkpoints and accrue interest
        advanceTimeWithCheckpoints(timeElapsed, variableInterest);

        // remove liquidity
        removeLiquidity(alice, aliceLpShares);

        // close the longs
        for (uint256 i = 0; i < numTrades; i++) {
            closeLong(bob, maturityTimeLong, bondAmounts[i]);
        }

        // longExposure should be 0
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        assertApproxEqAbs(poolInfo.longExposure, 0, 1);
        // idle should be equal to shareReserves
        uint256 expectedShareReserves = MockHyperdrive(address(hyperdrive))
            .calculateIdleShareReserves(hyperdrive.getPoolInfo().sharePrice) +
            hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }

    function test_netting_open_close_short() external {
        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a short is opened and immediately closed
        // - trade size is 1 million
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = 0;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a short is opened and closed after 182.5 days
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION / 2;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a short is opened and closed after 365 days
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This test case was failing in fuzzing. It tests
        // that when some shorts are closed via checkpoints
        // and some closed via explicit calls to closeShort,
        // it nets to zero.
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 0.5e18;
            int256 variableInterest = 0.0e18;
            uint256 timeElapsed = 8640001;
            uint256 tradeSize = 6283765.441079100693164485e18;
            uint256 numTrades = 5;
            open_close_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);
    }

    function open_close_short(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        // open a short
        uint256 shortAmount = tradeSize;
        uint256 maturityTimeShort = 0;
        for (uint256 i = 0; i < numTrades; i++) {
            (maturityTimeShort, ) = openShort(bob, shortAmount);
        }

        // fast forward time, create checkpoints and accrue interest
        advanceTimeWithCheckpoints(timeElapsed, variableInterest);

        // close the short
        for (uint256 i = 0; i < numTrades; i++) {
            closeShort(bob, maturityTimeShort, shortAmount);
        }

        // longExposure should be 0
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        assertApproxEqAbs(poolInfo.longExposure, 0, 1);
        // idle should be equal to shareReserves
        uint256 expectedShareReserves = MockHyperdrive(address(hyperdrive))
            .calculateIdleShareReserves(hyperdrive.getPoolInfo().sharePrice) +
            hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }

    // All tests close at maturity
    function test_netting_open_close_long_short() external {
        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - 1 trade
        // - trade size is 1 million
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = 0;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - 1 trade
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION / 2;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - 1 trade
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - 1000 trades
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1000;
            // You can increase the numTrades until the test fails from OutOfGas
            open_close_long_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - zero interest
        // - 1000 trades
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.0e18;
            uint256 timeElapsed = POSITION_DURATION;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1000;
            // You can increase the numTrades until the test fails from OutOfGas
            open_close_long_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);
    }

    function open_close_long_short(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) internal {
        // initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        // open positions
        uint256[] memory longMaturityTimes = new uint256[](numTrades);
        uint256[] memory shortMaturityTimes = new uint256[](numTrades);
        uint256[] memory bondAmounts = new uint256[](numTrades);
        for (uint256 i = 0; i < numTrades; i++) {
            uint256 basePaidLong = tradeSize;
            (uint256 maturityTimeLong, uint256 bondAmount) = openLong(
                bob,
                basePaidLong
            );
            longMaturityTimes[i] = maturityTimeLong;
            bondAmounts[i] = bondAmount;
            (uint256 maturityTimeShort, ) = openShort(bob, bondAmount);
            shortMaturityTimes[i] = maturityTimeShort;
        }

        // Checkpoint Exposure should be small even if there are many trades
        int256 checkpointExposure = int256(
            hyperdrive
                .getCheckpoint(HyperdriveUtils.latestCheckpoint(hyperdrive))
                .exposure
        );
        checkpointExposure = checkpointExposure < 0
            ? -checkpointExposure
            : checkpointExposure;
        assertLe(uint256(checkpointExposure), PRECISION_THRESHOLD * numTrades);

        // fast forward time, create checkpoints and accrue interest
        advanceTimeWithCheckpoints(timeElapsed, variableInterest);

        // remove liquidity
        removeLiquidity(alice, aliceLpShares);

        // Ensure all the positions have matured before trying to close them.
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        while (
            poolInfo.shortsOutstanding > 0 || poolInfo.longsOutstanding > 0
        ) {
            advanceTimeWithCheckpoints(POSITION_DURATION, variableInterest);
            poolInfo = hyperdrive.getPoolInfo();
        }

        // close positions
        for (uint256 i = 0; i < numTrades; i++) {
            // close the short positions
            closeShort(bob, shortMaturityTimes[i], bondAmounts[i]);

            // close the long positions
            closeLong(bob, longMaturityTimes[i], bondAmounts[i]);
        }

        // longExposure should be 0
        poolInfo = hyperdrive.getPoolInfo();
        assertApproxEqAbs(poolInfo.longExposure, 0, 1);

        // idle should be equal to shareReserves
        uint256 expectedShareReserves = MockHyperdrive(address(hyperdrive))
            .calculateIdleShareReserves(hyperdrive.getPoolInfo().sharePrice) +
            hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }

    function open_close_long_short_different_checkpoints(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) internal {
        // initialize the market
        uint256 aliceLpShares = 0;
        {
            uint256 apr = 0.05e18;
            deploy(alice, apr, initialSharePrice, 0, 0, 0);
            uint256 contribution = 500_000_000e18;
            aliceLpShares = initialize(alice, apr, contribution);

            // fast forward time and accrue interest
            advanceTime(POSITION_DURATION, variableInterest);
        }

        // open positions
        uint256[] memory longMaturityTimes = new uint256[](numTrades);
        uint256[] memory shortMaturityTimes = new uint256[](numTrades);
        uint256[] memory bondAmounts = new uint256[](numTrades);
        for (uint256 i = 0; i < numTrades; i++) {
            uint256 basePaidLong = tradeSize;
            (uint256 maturityTimeLong, uint256 bondAmount) = openLong(
                bob,
                basePaidLong
            );
            longMaturityTimes[i] = maturityTimeLong;
            bondAmounts[i] = bondAmount;

            // fast forward time, create checkpoints and accrue interest
            advanceTimeWithCheckpoints(timeElapsed, variableInterest);

            (uint256 maturityTimeShort, ) = openShort(bob, bondAmount);
            shortMaturityTimes[i] = maturityTimeShort;
        }
        removeLiquidity(alice, aliceLpShares);

        // Ensure all the positions have matured before trying to close them
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        while (
            poolInfo.shortsOutstanding > 0 || poolInfo.longsOutstanding > 0
        ) {
            advanceTimeWithCheckpoints(POSITION_DURATION, variableInterest);
            poolInfo = hyperdrive.getPoolInfo();
        }

        // close the short positions
        for (uint256 i = 0; i < numTrades; i++) {
            // close the short positions
            closeShort(bob, shortMaturityTimes[i], bondAmounts[i]);

            // close the long positions
            closeLong(bob, longMaturityTimes[i], bondAmounts[i]);
        }

        // longExposure should be 0
        poolInfo = hyperdrive.getPoolInfo();
        assertApproxEqAbs(poolInfo.longExposure, 0, 1);

        // idle should be equal to shareReserves
        uint256 expectedShareReserves = MockHyperdrive(address(hyperdrive))
            .calculateIdleShareReserves(hyperdrive.getPoolInfo().sharePrice) +
            hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }
}
