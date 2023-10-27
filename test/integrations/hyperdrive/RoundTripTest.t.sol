// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdError } from "forge-std/StdError.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract RoundTripTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function test_long_round_trip_immediately_at_checkpoint() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the poolInfo before opening the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Immediately close the long.
        closeLong(bob, maturityTime, bondAmount);

        // Get the poolInfo after closing the long.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        // if they aren't the same, then the pool should be the one that wins
        assertGe(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);
        // should be exact if out = in
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
    }

    function test_long_round_trip_immediately_halfway_thru_checkpoint()
        external
    {
        uint256 apr = 0.05e18;

        // Initialize the pool with capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the poolInfo before opening the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // fast forward time to halfway through checkpoint
        advanceTime(CHECKPOINT_DURATION / 2, 0);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Immediately close the long.
        closeLong(bob, maturityTime, bondAmount);

        // Get the poolInfo after closing the long.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        // if they aren't the same, then the pool should be the one that wins
        assertGe(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);
        // should be exact if out = in
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
    }

    function test_short_round_trip_immediately_at_checkpoint() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the poolInfo before opening the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Open a short position.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // Immediately close the short
        closeShort(bob, maturityTime, bondAmount);

        // Get the poolInfo after closing the short.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        // if they aren't the same, then the pool should be the one that wins
        assertGe(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);
        // should be exact if out = in
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
    }

    function test_short_round_trip_immediately_halfway_thru_checkpoint()
        external
    {
        uint256 apr = 0.05e18;

        // Initialize the pool with capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the poolInfo before opening the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // fast forward time to halfway through checkpoint
        advanceTime(CHECKPOINT_DURATION / 2, 0);

        // Open a short position.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // Immediately close the short.
        closeShort(bob, maturityTime, bondAmount);

        // Get the poolInfo after closing the short.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        // if they aren't the same, then the pool should be the one that wins
        assertGe(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);

        // should be exact if out = in
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
    }

    function test_sandwiched_long_round_trip() external {
        uint256 apr = 0.05e18;
        // Deploy the pool and initialize the market
        {
            uint256 timeStretchApr = 0.05e18;
            deploy(alice, timeStretchApr, 0, 0, 0);
        }
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Calculate how much profit would be made from a long sandwiched by shorts

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

        // if they aren't the same, then the pool should be the one that wins
        assertGe(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);
        // should be exact if out = in
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
    }

    // FIXME: Unignore this.
    //
    // TODO: Ignoring until the max spot price PR.
    function test_long_multiblock_round_trip_end_of_checkpoint(
        uint256 apr,
        uint256 timeStretchApr,
        uint256 basePaid
    ) internal {
        _test_long_multiblock_round_trip_end_of_checkpoint(
            apr,
            timeStretchApr,
            basePaid
        );
    }

    function test_long_multiblock_round_trip_end_of_checkpoint_edge_cases()
        external
    {
        uint256 snapshotId = vm.snapshot();
        {
            uint256 apr = 115792089237316195423570985008687907853269984665640564039457583990320674062335;
            uint256 timeStretchApr = 886936259672610464646559504023817532562726574141720139630650341263;
            uint256 basePaid = 65723876150308947051900890891865009457038319412461;
            _test_long_multiblock_round_trip_end_of_checkpoint(
                apr,
                timeStretchApr,
                basePaid
            );
        }
        vm.revertTo(snapshotId);

        // TODO: This test fails because the calculateMaxLong seems to be misbehaving.
        //       See issue #595
        // snapshotId = vm.snapshot();
        // {
        //     uint256 apr = 63203229717248733662763783222570;
        //     uint256 timeStretchApr = 3408059979187494427077136;
        //     uint256 basePaid = 57669888194155013968076316270639259357724635816572534634741412969387347636732;
        //     _test_long_multiblock_round_trip_end_of_checkpoint(
        //         apr,
        //         timeStretchApr,
        //         basePaid
        //     );
        // }
        // vm.revertTo(snapshotId);

        // TODO: This test fails because the calculateMaxLong seems to be misbehaving.
        //       See issue #595
        // uint256 apr = 115792089237316195423570985008687907853269984665640564039457583996916939587517; // 0.172756074408646686
        // uint256 timeStretchApr = 41280540007823693914881174596677236629628473357578130920607715; // 0.059510057259928604
        // uint256 basePaid = 3512909646876087064266547833688149281604992599057120012676367392282791491; // 3_942_239_358.711925131571174045
        // _test_long_multiblock_round_trip_end_of_checkpoint(
        //     apr,
        //     timeStretchApr,
        //     basePaid
        // );
    }

    function _test_long_multiblock_round_trip_end_of_checkpoint(
        uint256 apr,
        uint256 timeStretchApr,
        uint256 basePaid
    ) internal {
        apr = apr.normalizeToRange(0.001e18, .4e18);
        timeStretchApr = timeStretchApr.normalizeToRange(0.05e18, 0.4e18);

        // Deploy the pool and initialize the market
        uint256 curveFee = 0.05e18; // 5% of APR
        uint256 flatFee = 0.0005e18; // 5 bps
        deploy(alice, timeStretchApr, curveFee, flatFee, .015e18);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the poolInfo before opening the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // fast forward time to almost the end of the checkpoint
        advanceTime(CHECKPOINT_DURATION - 1, 0);

        // Open a long position.
        basePaid = basePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong()
        );
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // fast forward time to the end of the checkpoint
        advanceTime(1, 0);

        // Immediately close the long.
        closeLong(bob, maturityTime, bondAmount);

        // Get the poolInfo after closing the long.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        // if they aren't the same, then the pool should be the one that wins
        assertGe(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);
    }
}
