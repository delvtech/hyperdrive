// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { MockHyperdrive, IMockHyperdrive } from "../../../contracts/test/MockHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract IntraCheckpointNettingTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function test_netting_basic_example() external {
        uint256 initialVaultSharePrice = 1e18;

        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
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
            .calculateIdleShareReserves(
                hyperdrive.getPoolInfo().vaultSharePrice
            ) + hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }

    // This test was designed to show that a netted long and short can be closed
    // at maturity even if all liquidity is removed. This test would fail before
    // we added the logic:
    //
    // - to properly zero out exposure on checkpoint boundaries
    // - payout the withdrawal pool only when the idle capital is
    //   worth more than the active LP supply
    function test_netting_long_short_close_at_maturity() external {
        uint256 initialVaultSharePrice = 1e18;
        int256 variableInterest = 0;
        uint256 timeElapsed = 10220546; //~118 days between each trade
        uint256 tradeSize = 100e18;

        // initialize the market
        uint256 aliceLpShares = 0;
        {
            uint256 apr = 0.05e18;
            deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
            uint256 contribution = 500_000_000e18;
            aliceLpShares = initialize(alice, apr, contribution);

            // fast forward time and accrue interest
            advanceTime(POSITION_DURATION, 0);
        }

        // Celine adds liquidity. This is needed to allow the positions to be
        // closed out.
        addLiquidity(celine, 500_000_000e18);

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
            .calculateIdleShareReserves(
                hyperdrive.getPoolInfo().vaultSharePrice
            ) + hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }

    function test_netting_mismatched_exposure_maturities() external {
        uint256 initialVaultSharePrice = 1e18;
        int256 variableInterest = 0e18;
        uint256 timeElapsed = 10220546; //~118 days between each trade
        uint256 tradeSize = 100e18;

        // initialize the market
        uint256 aliceLpShares = 0;
        {
            uint256 apr = 0.05e18;
            deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
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
            .calculateIdleShareReserves(
                hyperdrive.getPoolInfo().vaultSharePrice
            ) + hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }

    // This test ensures that longs can't be closed when closing them would
    // cause the system to become insolvent. Prior to adding the solvency guard
    // to `closeLong`, this test would have failed.
    function test_netting_longs_insolvency() external {
        // initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, ONE, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, 0);

        // consume a lot of the pool's solvency
        openLong(bob, hyperdrive.calculateMaxLong());

        // fast forward a checkpoint
        advanceTime(CHECKPOINT_DURATION, 0);

        // open a large short
        openShort(bob, hyperdrive.calculateMaxShort());

        // open a long
        (uint256 maturityTime, uint256 bondAmount) = openLong(
            bob,
            hyperdrive.calculateMaxLong().mulDown(0.5e18)
        );

        // open another short
        openShort(bob, bondAmount);

        // try to close the long. this should fail due to insufficient liquidity.
        vm.expectRevert(IHyperdrive.InsufficientLiquidity.selector);
        closeLong(bob, maturityTime, bondAmount);
    }

    function test_netting_longs_close_with_initial_vault_share_price_gt_1()
        external
    {
        uint256 initialVaultSharePrice = 1.017375020334083692e18;
        int256 variableInterest = 0.050000000000000000e18;
        uint256 timeElapsed = 4924801;
        uint256 tradeSize = 3810533.716355891982851995e18;
        uint256 numTrades = 1;
        open_close_long(
            initialVaultSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    function test_netting_longs_can_close_with_no_shorts() external {
        uint256 initialVaultSharePrice = 1.000252541820033020e18;
        int256 variableInterest = 0.050000000000000000e18;
        uint256 timeElapsed = POSITION_DURATION / 2;
        uint256 tradeSize = 369599.308648593814273788e18;
        uint256 numTrades = 2;
        open_close_long(
            initialVaultSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    // This test demonstrates that you can open longs and shorts indefinitely until
    // the interest drops so low that positions can't be closed.
    function test_netting_extreme_negative_interest_time_elapsed() external {
        uint256 initialVaultSharePrice = 1e18;
        int256 variableInterest = -0.1e18; // NOTE: This is the lowest interest rate that can be used
        uint256 timeElapsed = 10220546; //~118 days between each trade
        uint256 tradeSize = 100e18;
        uint256 numTrades = 2;

        // If you increase numTrades enough it will eventually fail due to sub underflow
        // caused by share price going so low that k-y is negative (on openShort)
        open_close_long_short_different_checkpoints(
            initialVaultSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    function test_netting_zero_interest_small_time_elapsed() external {
        uint256 initialVaultSharePrice = 1e18;
        int256 variableInterest = 0e18;
        uint256 timeElapsed = CHECKPOINT_DURATION / 3;
        uint256 tradeSize = 100e18; //100_000_000 fails with sub underflow
        uint256 numTrades = 100;

        // If you increase trade size enough it will eventually fail due to sub underflow
        // caused by share price going so low that k-y is negative (on openShort)
        open_close_long_short_different_checkpoints(
            initialVaultSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    // This test shows that you can open/close long/shorts with extreme positive interest
    function test_netting_extreme_positive_interest_time_elapsed() external {
        uint256 initialVaultSharePrice = 0.5e18;
        int256 variableInterest = 0.5e18;
        uint256 timeElapsed = 15275477; // 176 days between each trade
        uint256 tradeSize = 504168.031667365798150347e18;
        uint256 numTrades = 100;

        // If you increase numTrades enough it will eventually fail in openLong()
        // due to minOutput > bondProceeds where minOutput = baseAmount from openLong()
        open_close_long_short_different_checkpoints(
            initialVaultSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    // This test shows that you can open large long/shorts repeatedly then wait 10 years to close all the positions
    function test_large_long_large_short_many_wait_to_redeem() external {
        uint256 initialVaultSharePrice = 1e18;
        int256 variableInterest = 1.05e18;
        uint256 timeElapsed = 3650 days; // 10 years
        uint256 tradeSize = 100_000_000e18;
        uint256 numTrades = 250;

        // You can keep increasing the numTrades until the test fails from
        // NegativeInterest on the openLong() spotPrice > 1 check
        open_close_long_short(
            initialVaultSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    /// forge-config: default.fuzz.runs = 1000
    function test_netting_fuzz(
        uint256 initialVaultSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) external {
        // Fuzz inputs Standard Range
        // initialVaultSharePrice [0.5,5]
        // variableInterest [0,50]
        // timeElapsed [0,365]
        // numTrades [1,5]
        // tradeSize [1,50_000_000/numTrades] 10% of the TVL
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            0.5e18,
            5e18
        );
        variableInterest = variableInterest.normalizeToRange(0e18, .5e18);
        timeElapsed = timeElapsed.normalizeToRange(0, POSITION_DURATION);
        numTrades = tradeSize.normalizeToRange(1, 5);
        tradeSize = tradeSize.normalizeToRange(1e18, 50_000_000e18 / numTrades);
        open_close_long(
            initialVaultSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        open_close_short(
            initialVaultSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        open_close_long_short(
            initialVaultSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
    }

    function test_netting_open_close_long() external {
        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long is opened and immediately closed
        // - trade size is 1 million
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = 0 days;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long(
                initialVaultSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long is opened and closed after 182.5 days
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION / 2;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long(
                initialVaultSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long is opened and closed after POSITION_DURATION
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long(
                initialVaultSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);
    }

    function open_close_long(
        uint256 initialVaultSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, apr, contribution);

        // Celine adds liquidity. This is needed to allow the positions to be
        // closed out.
        addLiquidity(celine, 500_000_000e18);

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
            .calculateIdleShareReserves(
                hyperdrive.getPoolInfo().vaultSharePrice
            ) + hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }

    function test_netting_open_close_short() external {
        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go to up
        // - a short is opened and immediately closed
        // - trade size is 1 million
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = 0;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_short(
                initialVaultSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go to up
        // - a short is opened and closed after 182.5 days
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION / 2;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_short(
                initialVaultSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go to up
        // - a short is opened and closed after 365 days
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_short(
                initialVaultSharePrice,
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
            uint256 initialVaultSharePrice = 0.5e18;
            int256 variableInterest = 0.0e18;
            uint256 timeElapsed = 8640001;
            uint256 tradeSize = 6283765.441079100693164485e18;
            uint256 numTrades = 5;
            open_close_short(
                initialVaultSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);
    }

    function open_close_short(
        uint256 initialVaultSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Celine adds liquidity. This is needed to allow the positions to be
        // closed out.
        addLiquidity(celine, 500_000_000e18);

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
            .calculateIdleShareReserves(
                hyperdrive.getPoolInfo().vaultSharePrice
            ) + hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }

    // All tests close at maturity
    function test_netting_open_close_long_short() external {
        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go to up
        // - 1 trade
        // - trade size is 1 million
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = 0;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long_short(
                initialVaultSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go to up
        // - 1 trade
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION / 2;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long_short(
                initialVaultSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go to up
        // - 1 trade
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long_short(
                initialVaultSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go to up
        // - 1000 trades
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1000;
            // You can increase the numTrades until the test fails from OutOfGas
            open_close_long_short(
                initialVaultSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - zero interest
        // - 1000 trades
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = 0.0e18;
            uint256 timeElapsed = POSITION_DURATION;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1000;
            // You can increase the numTrades until the test fails from OutOfGas
            open_close_long_short(
                initialVaultSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);
    }

    function open_close_long_short(
        uint256 initialVaultSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) internal {
        // initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);

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

        // The amount of non-netted longs should be equal to zero since the
        // bond amounts cancel out.
        assertEq(
            hyperdrive.getCheckpointExposure(hyperdrive.latestCheckpoint()),
            0
        );

        // fast forward time, create checkpoints and accrue interest
        advanceTimeWithCheckpoints(timeElapsed, variableInterest);

        // remove liquidity
        (, uint256 withdrawalShares) = removeLiquidity(alice, aliceLpShares);

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
        redeemWithdrawalShares(alice, withdrawalShares);

        // longExposure should be 0
        poolInfo = hyperdrive.getPoolInfo();
        assertApproxEqAbs(poolInfo.longExposure, 0, 1);

        // idle should be equal to shareReserves
        uint256 expectedShareReserves = MockHyperdrive(address(hyperdrive))
            .calculateIdleShareReserves(
                hyperdrive.getPoolInfo().vaultSharePrice
            ) + hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }

    function open_close_long_short_different_checkpoints(
        uint256 initialVaultSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) internal {
        // initialize the market
        uint256 aliceLpShares = 0;
        {
            uint256 apr = 0.05e18;
            deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
            // JR TODO: we should add this as a parameter to fuzz to ensure that we are solvent with withdrawal shares
            uint256 contribution = 500_000_000e18;
            aliceLpShares = initialize(alice, apr, contribution);

            // fast forward time and accrue interest
            advanceTime(POSITION_DURATION, variableInterest);
            hyperdrive.checkpoint(
                HyperdriveUtils.latestCheckpoint(hyperdrive),
                0
            );
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

            // Bob attempts to add liquidity. If this fails, we record a flag
            // and ensure that he can add liquidity after the short is opened.
            bool addLiquiditySuccess;
            vm.stopPrank();
            vm.startPrank(celine);
            uint256 contribution = 500_000_000e18;
            baseToken.mint(contribution);
            baseToken.approve(address(hyperdrive), contribution);
            try
                hyperdrive.addLiquidity(
                    contribution,
                    0, // min lp share price of 0
                    0, // min spot rate of 0
                    type(uint256).max, // max spot rate of uint256 max
                    IHyperdrive.Options({
                        destination: bob,
                        asBase: true,
                        extraData: new bytes(0) // unused
                    })
                )
            returns (uint256 lpShares) {
                // Adding liquidity succeeded, so we don't need to check again.
                addLiquiditySuccess = true;

                // Immediately remove the liquidity to avoid interfering with
                // the remaining test.
                removeLiquidity(bob, lpShares);
            } catch (bytes memory reason) {
                // Adding liquidity failed, so we need to try again after
                // opening a short.
                addLiquiditySuccess = true;

                // Ensure that the failure was caused by the present value
                // calculation failing.
                assertEq(
                    keccak256(reason),
                    keccak256(
                        abi.encodeWithSelector(
                            IHyperdrive.InvalidPresentValue.selector
                        )
                    )
                );
            }

            // Open a short position.
            (uint256 maturityTimeShort, ) = openShort(bob, bondAmount);
            shortMaturityTimes[i] = maturityTimeShort;

            // If adding liquidity failed, we try again to ensure that the LP
            // can add liquidity when the pool is net neutral.
            if (!addLiquiditySuccess) {
                // Attempt to add liquidity. This should succeed.
                uint256 lpShares = addLiquidity(bob, contribution);

                // Immediately remove the liquidity to avoid interfering with
                // the remaining test.
                removeLiquidity(bob, lpShares);
            }
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
        poolInfo = hyperdrive.getPoolInfo();

        // TODO: Enable this. It fails for test_netting_extreme_negative_interest_time_elapsed
        // (uint256 withdrawalProceeds, ) = redeemWithdrawalShares(
        //     alice,
        //     withdrawalShares
        // );

        // longExposure should be 0
        poolInfo = hyperdrive.getPoolInfo();
        assertApproxEqAbs(poolInfo.longExposure, 0, 1);

        // idle should be equal to shareReserves
        uint256 expectedShareReserves = MockHyperdrive(address(hyperdrive))
            .calculateIdleShareReserves(
                hyperdrive.getPoolInfo().vaultSharePrice
            ) + hyperdrive.getPoolConfig().minimumShareReserves;
        assertEq(poolInfo.shareReserves, expectedShareReserves);
    }

    function test_close_short_solvency_edge_fuzz(
        uint256 apr,
        uint256 timeStretchAPR,
        uint256 timeToMaturity,
        uint256 contribution
    ) external {
        // Normalize the test parameters.
        apr = apr.normalizeToRange(0.01e18, 0.2e18);
        timeStretchAPR = timeStretchAPR.normalizeToRange(0.02e18, 0.1e18);
        timeToMaturity = timeToMaturity.normalizeToRange(0.1e18, 0.9e18);
        contribution = contribution.normalizeToRange(
            100_000e18,
            100_000_000_000e18
        );

        // Run the test.
        _test_close_short_solvency(
            apr,
            timeStretchAPR,
            timeToMaturity,
            contribution
        );
    }

    function test_close_short_solvency_edge_cases() external {
        // NOTE: This is the edge case that was used in the Spearbit issue.
        uint256 apr = 0.1e18;
        uint256 timeStretchAPR = 0.02e18;
        uint256 timeToMaturity = 0.5e18;
        uint256 contribution = 500e18;
        _test_close_short_solvency(
            apr,
            timeStretchAPR,
            timeToMaturity,
            contribution
        );
    }

    function _test_close_short_solvency(
        uint256 apr,
        uint256 timeStretchAPR,
        uint256 timeToMaturity,
        uint256 contribution
    ) internal {
        // Deploy the pool and initialize the market
        deploy(alice, timeStretchAPR, 0, 0, 0, 0);
        initialize(alice, apr, contribution);
        contribution -= 2 * hyperdrive.getPoolConfig().minimumShareReserves;

        // Open long and short positions that net out.
        uint256 longBase = hyperdrive.calculateMaxLong();
        (uint256 maturityTime, uint256 nettedBondAmount) = openLong(
            celine,
            longBase
        );
        openShort(celine, nettedBondAmount);
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                celine
            ),
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                celine
            )
        );

        // Open a max long that eats up any remaining liquidity that could be
        // used to close the short.
        longBase = hyperdrive.calculateMaxLong();
        openLong(celine, longBase);

        // Time passes without interest accruing.
        uint256 timeAdvanced = POSITION_DURATION.mulDown(timeToMaturity);
        advanceTime(timeAdvanced, int256(0));

        // Celine closes her short. This should fail since the pool becomes
        // insolvent if the short can be closed.
        vm.expectRevert();
        closeShort(celine, maturityTime, nettedBondAmount);

        // The term passes without interest accruing.
        advanceTime(POSITION_DURATION - timeAdvanced, int256(0));

        // A checkpoint is minted which should succeed. This indicates that
        // all of the longs and shorts could be closed.
        hyperdrive.checkpoint(maturityTime, 0);
    }
}
