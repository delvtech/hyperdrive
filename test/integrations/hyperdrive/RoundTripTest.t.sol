// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";
import "forge-std/console2.sol";

contract RoundTripTest is HyperdriveTest {
    using FixedPointMath for uint256;
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
        uint256 basePaid = 50_000_000e18;
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

    function test_long_multiblock_round_trip_end_of_checkpoint(
        uint256 apr, 
        uint256 timeStretchApr,
        uint256 basePaid
    )
        external
    {
        apr = apr.normalizeToRange(0.001e18,.4e18);
        timeStretchApr = timeStretchApr.normalizeToRange(0.05e18,0.4e18);
        console2.log("apr", apr.toString(18));
        console2.log("timeStretchApr", timeStretchApr.toString(18));

        // Deploy the pool and initialize the market
        uint256 curveFee = 0.05e18;  // 5% of APR
        uint256 flatFee = 0.0005e18; // 5 bps
        deploy(alice, timeStretchApr, curveFee, flatFee, .015e18);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // NOTE: There is a relationship between min(basePaid), contribution, apr and timestretchAPR 
        // that must be satisfied to preven subOverflow in calculateBondsOutGivenSharesIn().abi
        // The relationship is:
        // subOverflow happens with a low ratio of basePaid/contribution
        // subOverflow happens with a low timeStretchAPR and a high APR
        // e.g. (apr: 57% time stretch apr: 5% basePaid: 1e14 contribution: 500 million)

        // NOTE: The following condition results in a small loss to the LP
        // apr: 49.9% basePaid: 1e14 contribution: 500 million
        // timeStretchAPR doesn't impact the loss 
        // -> higher fees fix this
        // -> changing min(basePaid) to 1e15 fixes this
        // reserves go from 500_000_000e18 to 499_999_999.999999167490380404
        basePaid = basePaid.normalizeToRange(
            1e14,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        console2.log("basePaid", basePaid.toString(18));

        // Get the poolInfo before opening the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // fast forward time to almost the end of the checkpoint
        advanceTime(CHECKPOINT_DURATION - 1, 0);

        // Open a long position.
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // fast forward time to the end of the checkpoint
        advanceTime(1, 0);

        // Immediately close the long.
        closeLong(bob, maturityTime, bondAmount);

        // Get the poolInfo after closing the long.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();
        console2.log("poolInfoAfter.shareReserves", poolInfoAfter.shareReserves.toString(18));

        // if they aren't the same, then the pool should be the one that wins
        assertGe(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);
    }
}
