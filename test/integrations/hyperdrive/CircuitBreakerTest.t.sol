// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { stdError } from "forge-std/StdError.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

import "forge-std/console2.sol";

contract CircuitBreakerTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function test_circuit_breaker_triggered() external {
        // Ensure a feasible fixed rate.
        uint256 fixedRate = 0.05e18;

        // Ensure a feasible time stretch fixed rate.
        uint256 timeStretchFixedRate = fixedRate;

        // Deploy the pool and initialize the market
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchFixedRate,
            POSITION_DURATION
        );
        config.maximumAddLiquidityAPRDelta = 1e18;
        deploy(alice, config);
        uint256 contribution = 10_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a max short position.
        uint256 shortSize = hyperdrive.calculateMaxShort();
        (uint256 maturityTime, ) = openShort(bob, shortSize);
        
        // Add liquidity should revert.
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        vm.expectRevert(IHyperdrive.CircuitBreakerTriggered.selector);
        hyperdrive.addLiquidity(                
            contribution,
            0, // min lp share price of 0
            0, // min spot rate of 0
            type(uint256).max, // max spot rate of uint256 max
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0) // unused
            })
        );
    }

    function test_weighted_average_spot_price() external {
        // Ensure a feasible fixed rate.
        uint256 fixedRate = 0.05e18;

        // Ensure a feasible time stretch fixed rate.
        uint256 timeStretchFixedRate = fixedRate;

        // Deploy the pool and initialize the market
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchFixedRate,
            POSITION_DURATION
        );
        config.maximumAddLiquidityAPRDelta = 1e18;
        deploy(alice, config);
        uint256 contribution = 10_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Advance time through most of a checkpoint.
        advanceTime(CHECKPOINT_DURATION - 1 hours, 0);
        uint256 weightedSpotPriceBefore = hyperdrive.getCheckpoint(
            HyperdriveUtils.latestCheckpoint(hyperdrive)
        ).weightedSpotPrice;

        // Open a max short position.
        uint256 shortSize = hyperdrive.calculateMaxShort();
        (uint256 maturityTime, ) = openShort(bob, shortSize);
        uint256 actualSpotPrice =  HyperdriveUtils.calculateSpotPrice(
            hyperdrive
        );

        // Advance time to the next checkpoint.
        advanceTime(1 hours, 0);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);

        uint256 weightedSpotPriceAfter = hyperdrive.getCheckpoint(
            HyperdriveUtils.latestCheckpoint(hyperdrive) - CHECKPOINT_DURATION
        ).weightedSpotPrice;

        // Check that the new checkpoint's weighted spot price is less than
        // the old checkpoint's weighted spot price.
        assertLt(weightedSpotPriceAfter, weightedSpotPriceBefore);

        // Check that the checkpoint's weighted spot price is greater than the 
        // actual spot price.
        assertGt(weightedSpotPriceAfter, actualSpotPrice);

        // Check that the actual spot price is not equal to the previous 
        // checkpoint's weighted spot price.
        assertFalse(actualSpotPrice == weightedSpotPriceBefore);
    }

        /// forge-config: default.fuzz.runs = 1000
    function test_weighted_average_skipped_checkpoint() external {
        uint256 fixedRate = 0.035e18;
        uint256 initialLiquidity = 500_000_000e18;

        uint256 zombieShareReserves1;
        uint256 shareReserves1;
        {
            // Initialize the pool with capital.
            deploy(bob, fixedRate, 1e18, 0, 0, 0, 0);
            initialize(bob, fixedRate, 2 * MINIMUM_SHARE_RESERVES);

            // Alice adds liquidity.
            addLiquidity(alice, initialLiquidity);

            // Open a max short position.
            uint256 shortSize = hyperdrive.calculateMaxShort();
            (uint256 maturityTime, ) = openShort(bob, shortSize);

            // One term passes and shorts mature.
            advanceTime(POSITION_DURATION, 0);
            hyperdrive.checkpoint(
                HyperdriveUtils.latestCheckpoint(hyperdrive),
                0
            );

            // A checkpoints is missed.
            advanceTime(CHECKPOINT_DURATION, 0);
            uint256 missedCheckpointTime = block.timestamp;
            uint256 weightedSpotPriceMissed = hyperdrive.getCheckpoint(
               missedCheckpointTime
            ).weightedSpotPrice;

            // The weighted spot price at the missed checkpoint
            // should be zero.
            assertEq(weightedSpotPriceMissed, 0);

            // Several checkpoints are minted.
            advanceTimeWithCheckpoints2(3 * CHECKPOINT_DURATION, 0);
            uint256 currentSpotPrice =  HyperdriveUtils.calculateSpotPrice(
                hyperdrive
            );

            // Mint the missed checkpoint.
            hyperdrive.checkpoint(missedCheckpointTime, 0);
            uint256 weightedSpotPriceMinted = hyperdrive.getCheckpoint(
               missedCheckpointTime
            ).weightedSpotPrice;


            // The missed checkpoint has now been minted. The
            // weighted spot price should be equal to the current
            // spot price.
            assertEq(weightedSpotPriceMinted, currentSpotPrice);
        }
    }
}
