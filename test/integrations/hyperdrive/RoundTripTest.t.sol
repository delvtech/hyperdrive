// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdError } from "forge-std/StdError.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "../../../contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract RoundTripTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    /// forge-config: default.fuzz.runs = 1000
    function test_long_round_trip_immediately_at_checkpoint(
        uint256 fixedRate,
        uint256 timeStretchFixedRate,
        uint256 basePaid
    ) external {
        // Ensure a feasible fixed rate.
        fixedRate = fixedRate.normalizeToRange(0.001e18, 0.50e18);

        // Ensure a feasible time stretch fixed rate.
        uint256 lowerBound = fixedRate.divDown(2e18).max(0.005e18);
        uint256 upperBound = lowerBound.max(fixedRate).mulDown(2e18);
        timeStretchFixedRate = timeStretchFixedRate.normalizeToRange(
            lowerBound,
            upperBound
        );

        // Deploy the pool and initialize the market
        deploy(alice, timeStretchFixedRate, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Ensure a feasible trade size.
        basePaid = basePaid.normalizeToRange(
            2 * MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong() - MINIMUM_TRANSACTION_AMOUNT
        );

        // Get the poolInfo before opening the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Open a long position.
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Immediately close the long.
        closeLong(bob, maturityTime, bondAmount);

        // Get the poolInfo after closing the long.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        // If they aren't the same, then the pool should be the one that wins.

        assertGe(
            poolInfoAfter.shareReserves + 1e12,
            poolInfoBefore.shareReserves
        );

        // Should be exact if out = in.
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
    }

    /// forge-config: default.fuzz.runs = 1000
    function test_long_round_trip_immediately_partially_thru_checkpoint(
        uint256 fixedRate,
        uint256 timeStretchFixedRate,
        uint256 basePaid,
        uint256 timeDelta
    ) external {
        // Ensure a feasible fixed rate.
        fixedRate = fixedRate.normalizeToRange(0.001e18, 0.50e18);

        // Ensure a feasible time stretch fixed rate.
        uint256 lowerBound = fixedRate.divDown(2e18).max(0.005e18);
        uint256 upperBound = lowerBound.max(fixedRate).mulDown(2e18);
        timeStretchFixedRate = timeStretchFixedRate.normalizeToRange(
            lowerBound,
            upperBound
        );

        // Deploy the pool and initialize the market
        deploy(alice, timeStretchFixedRate, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Ensure a feasible trade size.
        basePaid = basePaid.normalizeToRange(
            2 * MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong() - MINIMUM_TRANSACTION_AMOUNT
        );

        // Calculate time elapsed.
        timeDelta = timeDelta.normalizeToRange(0, CHECKPOINT_DURATION - 1);

        // Fast forward time.
        advanceTime(timeDelta, 0);

        // Get the poolInfo before opening the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Open a long position.
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Immediately close the long.
        closeLong(bob, maturityTime, bondAmount);

        // Get the poolInfo after closing the long.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        // If they aren't the same, then the pool should be the one that wins.
        assertGe(
            poolInfoAfter.shareReserves + 1e12,
            poolInfoBefore.shareReserves
        );

        // Should be exact if out = in.
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
    }

    /// forge-config: default.fuzz.runs = 1000
    function test_long_round_trip_immediately_with_fees(
        uint256 fixedRate,
        uint256 timeStretchFixedRate,
        uint256 basePaid
    ) external {
        // Ensure a feasible fixed rate.
        fixedRate = fixedRate.normalizeToRange(0.001e18, 0.50e18);

        // Ensure a feasible time stretch fixed rate.
        uint256 lowerBound = fixedRate.divDown(2e18).max(0.005e18);
        uint256 upperBound = lowerBound.max(fixedRate).mulDown(2e18);
        timeStretchFixedRate = timeStretchFixedRate.normalizeToRange(
            lowerBound,
            upperBound
        );

        // Deploy the pool and initialize the market
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchFixedRate,
            POSITION_DURATION
        );
        config.fees.curve = 0.1e18;
        config.fees.governanceLP = 1e18;
        deploy(alice, config);
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Ensure a feasible trade size.
        basePaid = basePaid.normalizeToRange(
            2 * MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong() - MINIMUM_TRANSACTION_AMOUNT
        );

        // Bob opens a long position.
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Bob immediately closes his long position.
        IHyperdrive.PoolInfo memory infoBefore = hyperdrive.getPoolInfo();
        closeLong(bob, maturityTime, bondAmount);

        // Ensure that the share adjustment wasn't changed.
        assertEq(
            hyperdrive.getPoolInfo().shareAdjustment,
            infoBefore.shareAdjustment
        );
    }

    /// forge-config: default.fuzz.runs = 1000
    function test_short_round_trip_immediately_at_checkpoint(
        uint256 fixedRate,
        uint256 timeStretchFixedRate,
        uint256 shortSize
    ) external {
        // Ensure a feasible fixed rate.
        fixedRate = fixedRate.normalizeToRange(0.001e18, 0.50e18);

        // Ensure a feasible time stretch fixed rate.
        uint256 lowerBound = fixedRate.divDown(2e18).max(0.005e18);
        uint256 upperBound = lowerBound.max(fixedRate).mulDown(2e18);
        timeStretchFixedRate = timeStretchFixedRate.normalizeToRange(
            lowerBound,
            upperBound
        );

        // Deploy the pool and initialize the market
        deploy(alice, timeStretchFixedRate, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Ensure a feasible trade size.
        shortSize = shortSize.normalizeToRange(
            2 * MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxShort().mulDown(0.9e18)
        );

        // Get the poolInfo before opening the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Open a short position.
        (uint256 maturityTime, ) = openShort(bob, shortSize);

        // Immediately close the short.
        closeShort(bob, maturityTime, shortSize);

        // Get the poolInfo after closing the short.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        // If they aren't the same, then the pool should be the one that wins.
        assertGe(
            poolInfoAfter.shareReserves + 1e12,
            poolInfoBefore.shareReserves
        );

        // Should be exact if out = in.
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
    }

    /// forge-config: default.fuzz.runs = 1000
    function test_short_round_trip_immediately_partially_thru_checkpoint(
        uint256 fixedRate,
        uint256 timeStretchFixedRate,
        uint256 shortSize,
        uint256 timeDelta
    ) external {
        // Ensure a feasible fixed rate.
        fixedRate = fixedRate.normalizeToRange(0.001e18, 0.50e18);

        // Ensure a feasible time stretch fixed rate.
        uint256 lowerBound = fixedRate.divDown(2e18).max(0.005e18);
        uint256 upperBound = lowerBound.max(fixedRate).mulDown(2e18);
        timeStretchFixedRate = timeStretchFixedRate.normalizeToRange(
            lowerBound,
            upperBound
        );

        // Deploy the pool and initialize the market
        deploy(alice, timeStretchFixedRate, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Ensure a feasible trade size.
        shortSize = shortSize.normalizeToRange(
            2 * MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxShort() - MINIMUM_TRANSACTION_AMOUNT
        );

        // Calculate time elapsed.
        timeDelta = timeDelta.normalizeToRange(0, CHECKPOINT_DURATION - 1);

        // Fast forward time to halfway through checkpoint.
        advanceTime(timeDelta, 0);

        // Get the poolInfo before opening the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Open a short position.
        (uint256 maturityTime, ) = openShort(bob, shortSize);

        // Immediately close the short.
        closeShort(bob, maturityTime, shortSize);

        // Get the poolInfo after closing the short.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        // If they aren't the same, then the pool should be the one that wins.
        assertGe(
            poolInfoAfter.shareReserves + 1e12,
            poolInfoBefore.shareReserves
        );

        // Should be exact if out = in.
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
    }

    /// forge-config: default.fuzz.runs = 1000
    function test_short_round_trip_immediately_with_fees(
        uint256 fixedRate,
        uint256 timeStretchFixedRate,
        uint256 shortAmount
    ) external {
        // Ensure a feasible fixed rate.
        fixedRate = fixedRate.normalizeToRange(0.001e18, 0.50e18);

        // Ensure a feasible time stretch fixed rate.
        uint256 lowerBound = fixedRate.divDown(2e18).max(0.005e18);
        uint256 upperBound = lowerBound.max(fixedRate).mulDown(2e18);
        timeStretchFixedRate = timeStretchFixedRate.normalizeToRange(
            lowerBound,
            upperBound
        );

        // Deploy the pool and initialize the market
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchFixedRate,
            POSITION_DURATION
        );
        config.fees.curve = 0.01e18;
        config.fees.governanceLP = 1e18;
        deploy(alice, config);
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Ensure a feasible trade size.
        shortAmount = shortAmount.normalizeToRange(
            2 * MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxShort().mulDown(0.9e18)
        );

        // Bob opens a short position.
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // Bob immediately closes his short position.
        IHyperdrive.PoolInfo memory infoBefore = hyperdrive.getPoolInfo();
        closeShort(bob, maturityTime, shortAmount);

        // Ensure that the share adjustment wasn't changed.
        assertEq(
            hyperdrive.getPoolInfo().shareAdjustment,
            infoBefore.shareAdjustment
        );
    }

    /// forge-config: default.fuzz.runs = 1000
    function test_sandwiched_long_round_trip(
        uint256 fixedRate,
        uint256 timeStretchFixedRate
    ) external {
        // Ensure a feasible fixed rate.
        fixedRate = fixedRate.normalizeToRange(0.001e18, 0.50e18);

        // Ensure a feasible time stretch fixed rate.
        uint256 lowerBound = fixedRate.divDown(2e18).max(0.005e18);
        uint256 upperBound = lowerBound.max(fixedRate).mulDown(2e18);
        timeStretchFixedRate = timeStretchFixedRate.normalizeToRange(
            lowerBound,
            upperBound
        );

        // Deploy the pool and initialize the market
        deploy(alice, timeStretchFixedRate, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Bob opens a short.
        uint256 bondsShorted = 10_000_000e18;
        (uint256 shortMaturityTime, ) = openShort(bob, bondsShorted);

        // Celine opens a long.
        uint256 basePaid = 10_000_000e18;
        (uint256 longMaturityTime, uint256 bondsReceived) = openLong(
            celine,
            basePaid
        );

        // Bob immediately closes short.
        closeShort(bob, shortMaturityTime, bondsShorted);

        // Celine closes long.
        closeLong(celine, longMaturityTime, bondsReceived);
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        // If they aren't the same, then the pool should be the one that wins.
        assertGe(
            poolInfoAfter.shareReserves + 1e12,
            poolInfoBefore.shareReserves
        );

        // Should be exact if out = in.
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
    }

    /// forge-config: default.fuzz.runs = 1000
    function test_long_multiblock_round_trip_end_of_checkpoint(
        uint256 fixedRate,
        uint256 timeStretchFixedRate,
        uint256 basePaid
    ) external {
        _test_long_multiblock_round_trip_end_of_checkpoint(
            fixedRate,
            timeStretchFixedRate,
            basePaid
        );
    }

    function test_long_multiblock_round_trip_end_of_checkpoint_edge_cases()
        external
    {
        uint256 snapshotId = vm.snapshot();
        {
            uint256 fixedRate = 115792089237316195423570985008687907853269984665640564039457583990320674062335;
            uint256 timeStretchFixedRate = 886936259672610464646559504023817532562726574141720139630650341263;
            uint256 basePaid = 65723876150308947051900890891865009457038319412461;
            _test_long_multiblock_round_trip_end_of_checkpoint(
                fixedRate,
                timeStretchFixedRate,
                basePaid
            );
        }
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        {
            uint256 fixedRate = 63203229717248733662763783222570;
            uint256 timeStretchFixedRate = 3408059979187494427077136;
            uint256 basePaid = 57669888194155013968076316270639259357724635816572534634741412969387347636732;
            _test_long_multiblock_round_trip_end_of_checkpoint(
                fixedRate,
                timeStretchFixedRate,
                basePaid
            );
        }
        vm.revertTo(snapshotId);
        {
            uint256 fixedRate = 115792089237316195423570985008687907853269984665640564039457583996916939587517; // 0.172756074408646686
            uint256 timeStretchFixedRate = 41280540007823693914881174596677236629628473357578130920607715; // 0.059510057259928604
            uint256 basePaid = 3512909646876087064266547833688149281604992599057120012676367392282791491; // 3_942_239_358.711925131571174045
            _test_long_multiblock_round_trip_end_of_checkpoint(
                fixedRate,
                timeStretchFixedRate,
                basePaid
            );
        }
    }

    function _test_long_multiblock_round_trip_end_of_checkpoint(
        uint256 fixedRate,
        uint256 timeStretchFixedRate,
        uint256 basePaid
    ) internal {
        // Ensure a feasible fixed rate.
        fixedRate = fixedRate.normalizeToRange(0.001e18, 0.50e18);

        // Ensure a feasible time stretch fixed rate.
        uint256 lowerBound = fixedRate.divDown(2e18).max(0.005e18);
        uint256 upperBound = lowerBound.max(fixedRate).mulDown(2e18);
        timeStretchFixedRate = timeStretchFixedRate.normalizeToRange(
            lowerBound,
            upperBound
        );

        // Deploy the pool and initialize the market
        uint256 curveFee = 0.01e18;
        uint256 flatFee = 0.0001e18;
        deploy(
            alice,
            timeStretchFixedRate,
            curveFee,
            flatFee,
            0.15e18,
            0.15e18
        );
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Get the poolInfo before opening the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Fast forward time to almost the end of the checkpoint.
        advanceTime(CHECKPOINT_DURATION - 1, 0);

        // Open a long position.
        basePaid = basePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong()
        );
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Fast forward time to the end of the checkpoint.
        advanceTime(1, 0);

        // Immediately close the long.
        closeLong(bob, maturityTime, bondAmount);

        // Get the poolInfo after closing the long.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        // If they aren't the same, then the pool should be the one that wins.
        assertGe(
            poolInfoAfter.shareReserves + 1e12,
            poolInfoBefore.shareReserves
        );
    }
}
