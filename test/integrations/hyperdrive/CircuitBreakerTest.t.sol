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

contract CircuitBreakerTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function test_circuit_breaker_triggered() external {
        // This test triggers the first circuit breaker condition.
        {
            // Ensure a feasible fixed rate.
            uint256 fixedRate = 0.05e18;

            // Ensure a feasible time stretch fixed rate.
            uint256 timeStretchFixedRate = fixedRate;

            // Deploy the pool and initialize the market.
            IHyperdrive.PoolConfig memory config = testConfig(
                timeStretchFixedRate,
                POSITION_DURATION
            );
            config.circuitBreakerDelta = 1e18;
            deploy(alice, config);
            uint256 contribution = 10_000_000e18;
            initialize(alice, fixedRate, contribution);

            // Open a max short position.
            uint256 shortSize = hyperdrive.calculateMaxShort();
            openShort(bob, shortSize);

            // Add liquidity should revert because the spot apr is
            // greater than the weighted average spot apr plus the delta.
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

        // This test triggers the second circuit breaker condition.
        {
            // Ensure a feasible fixed rate.
            uint256 fixedRate = 0.05e18;

            // Ensure a feasible time stretch fixed rate.
            uint256 timeStretchFixedRate = fixedRate;

            // Deploy the pool and initialize the market.
            IHyperdrive.PoolConfig memory config = testConfig(
                timeStretchFixedRate,
                POSITION_DURATION
            );
            config.circuitBreakerDelta = 1e18;
            deploy(alice, config);
            uint256 contribution = 10_000_000e18;
            initialize(alice, fixedRate, contribution);

            // Open a max short position.
            uint256 shortSize = hyperdrive.calculateMaxShort();
            openShort(bob, shortSize);

            // Fast forward to position maturity.
            advanceTimeWithCheckpoints2(POSITION_DURATION, 0);

            // Open a max long position.
            uint256 longSize = hyperdrive.calculateMaxLong();
            openLong(bob, longSize);

            // Add liquidity should revert because the weighted spot apr
            // is greater than the delta and the spot apr is less than
            // the weighted minus the spot apr.
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

        // This test ensures that the circuit breaker won't be affected by
        // changes to the spot rate in the current checkpoint.
        {
            // Ensure a feasible fixed rate.
            uint256 fixedRate = 0.05e18;

            // Ensure a feasible time stretch fixed rate.
            uint256 timeStretchFixedRate = fixedRate;

            // Deploy the pool and initialize the market.
            IHyperdrive.PoolConfig memory config = testConfig(
                timeStretchFixedRate,
                POSITION_DURATION
            );
            config.circuitBreakerDelta = 0.01e18; // 1% circuit breaker delta
            deploy(alice, config);
            uint256 contribution = 10_000_000e18;
            initialize(alice, fixedRate, contribution);

            // Advance a checkpoint.
            advanceTimeWithCheckpoints2(CHECKPOINT_DURATION, 0);

            // Open a max long position.
            uint256 longSize = hyperdrive.calculateMaxLong();
            openLong(bob, longSize);

            // Advance time to near the end of the current checkpoint.
            advanceTime(CHECKPOINT_DURATION.mulDown(0.99e18), 0);

            // Open a small trade to update the weighted spot price.
            openShort(bob, MINIMUM_TRANSACTION_AMOUNT);

            // Add liquidity should revert because the weighted spot apr
            // is greater than the delta and the spot apr is less than
            // the weighted minus the spot apr.
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
    }

    function test_weighted_average_spot_price_short() external {
        // Ensure a feasible fixed rate.
        uint256 fixedRate = 0.05e18;

        // Ensure a feasible time stretch fixed rate.
        uint256 timeStretchFixedRate = fixedRate;

        // Deploy the pool and initialize the market
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchFixedRate,
            POSITION_DURATION
        );
        config.circuitBreakerDelta = 1e18;
        deploy(alice, config);
        uint256 contribution = 10_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Advance time through most of a checkpoint.
        advanceTime(CHECKPOINT_DURATION - 1 hours, 0);
        uint256 weightedSpotPriceBefore = hyperdrive
            .getCheckpoint(HyperdriveUtils.latestCheckpoint(hyperdrive))
            .weightedSpotPrice;

        // Open a max short position.
        uint256 shortSize = hyperdrive.calculateMaxShort();
        openShort(bob, shortSize);
        uint256 actualSpotPrice = HyperdriveUtils.calculateSpotPrice(
            hyperdrive
        );

        // Advance time to the next checkpoint.
        advanceTime(1 hours, 0);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);

        uint256 weightedSpotPriceAfter = hyperdrive
            .getCheckpoint(
                HyperdriveUtils.latestCheckpoint(hyperdrive) -
                    CHECKPOINT_DURATION
            )
            .weightedSpotPrice;

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

    function test_weighted_average_spot_price_long() external {
        // Ensure a feasible fixed rate.
        uint256 fixedRate = 0.05e18;

        // Ensure a feasible time stretch fixed rate.
        uint256 timeStretchFixedRate = fixedRate;

        // Deploy the pool and initialize the market
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchFixedRate,
            POSITION_DURATION
        );
        config.circuitBreakerDelta = 1e18;
        deploy(alice, config);
        uint256 contribution = 10_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Advance time through most of a checkpoint.
        advanceTime(CHECKPOINT_DURATION - 1 hours, 0);
        uint256 weightedSpotPriceBefore = hyperdrive
            .getCheckpoint(HyperdriveUtils.latestCheckpoint(hyperdrive))
            .weightedSpotPrice;

        // Open a max long position.
        uint256 longSize = hyperdrive.calculateMaxLong();
        openLong(bob, longSize);
        uint256 actualSpotPrice = HyperdriveUtils.calculateSpotPrice(
            hyperdrive
        );

        // Advance time to the next checkpoint.
        advanceTime(1 hours, 0);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);

        uint256 weightedSpotPriceAfter = hyperdrive
            .getCheckpoint(
                HyperdriveUtils.latestCheckpoint(hyperdrive) -
                    CHECKPOINT_DURATION
            )
            .weightedSpotPrice;

        // Check that the new checkpoint's weighted spot price is greater than
        // the old checkpoint's weighted spot price.
        assertGt(weightedSpotPriceAfter, weightedSpotPriceBefore);

        // Check that the checkpoint's weighted spot price is less than the
        // actual spot price.
        assertLt(weightedSpotPriceAfter, actualSpotPrice);

        // Check that the actual spot price is not equal to the previous
        // checkpoint's weighted spot price.
        assertFalse(actualSpotPrice == weightedSpotPriceBefore);
    }

    function test_weighted_average_spot_price_instantaneous_long() external {
        // Ensure a feasible fixed rate.
        uint256 fixedRate = 0.05e18;

        // Ensure a feasible time stretch fixed rate.
        uint256 timeStretchFixedRate = fixedRate;

        // Deploy the pool and initialize the market.
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchFixedRate,
            POSITION_DURATION
        );
        config.circuitBreakerDelta = 1e18;
        deploy(alice, config);
        uint256 contribution = 10_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Get the current weighted spot price.
        uint256 weightedSpotPriceBefore = hyperdrive
            .getCheckpoint(HyperdriveUtils.latestCheckpoint(hyperdrive))
            .weightedSpotPrice;

        // Open a large long in the same block.
        openLong(alice, hyperdrive.calculateMaxLong());
        uint256 spotPriceAfterLong = hyperdrive.calculateSpotPrice();

        // Ensure that the weighted spot price is equal to the previous weighted
        // spot price.
        uint256 weightedSpotPriceAfter = hyperdrive
            .getCheckpoint(HyperdriveUtils.latestCheckpoint(hyperdrive))
            .weightedSpotPrice;
        assertEq(weightedSpotPriceAfter, weightedSpotPriceBefore);

        // A checkpoint passes.
        advanceTimeWithCheckpoints2(CHECKPOINT_DURATION, 0);

        // Ensure that the weighted spot price from the previous checkpoint is
        // equal to the spot price after opening the long.
        weightedSpotPriceAfter = hyperdrive
            .getCheckpoint(
                HyperdriveUtils.latestCheckpoint(hyperdrive) -
                    CHECKPOINT_DURATION
            )
            .weightedSpotPrice;
        assertEq(weightedSpotPriceAfter, spotPriceAfterLong);
    }

    function test_weighted_average_spot_price_instantaneous_short() external {
        // Ensure a feasible fixed rate.
        uint256 fixedRate = 0.05e18;

        // Ensure a feasible time stretch fixed rate.
        uint256 timeStretchFixedRate = fixedRate;

        // Deploy the pool and initialize the market.
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchFixedRate,
            POSITION_DURATION
        );
        config.circuitBreakerDelta = 1e18;
        deploy(alice, config);
        uint256 contribution = 10_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Get the current weighted spot price.
        uint256 weightedSpotPriceBefore = hyperdrive
            .getCheckpoint(HyperdriveUtils.latestCheckpoint(hyperdrive))
            .weightedSpotPrice;

        // Open a large short in the same block.
        openShort(alice, hyperdrive.calculateMaxShort());
        uint256 spotPriceAfterShort = hyperdrive.calculateSpotPrice();

        // Ensure that the weighted spot price is equal to the previous weighted
        // spot price.
        uint256 weightedSpotPriceAfter = hyperdrive
            .getCheckpoint(HyperdriveUtils.latestCheckpoint(hyperdrive))
            .weightedSpotPrice;
        assertEq(weightedSpotPriceAfter, weightedSpotPriceBefore);

        // A checkpoint passes.
        advanceTimeWithCheckpoints2(CHECKPOINT_DURATION, 0);

        // Ensure that the weighted spot price from the previous checkpoint is
        // equal to the spot price after opening the short.
        weightedSpotPriceAfter = hyperdrive
            .getCheckpoint(
                HyperdriveUtils.latestCheckpoint(hyperdrive) -
                    CHECKPOINT_DURATION
            )
            .weightedSpotPrice;
        assertEq(weightedSpotPriceAfter, spotPriceAfterShort);
    }

    /// forge-config: default.fuzz.runs = 1000
    function test_weighted_average_skipped_checkpoint() external {
        uint256 fixedRate = 0.035e18;
        uint256 initialLiquidity = 500_000_000e18;

        // Initialize the pool with capital.
        deploy(bob, fixedRate, 1e18, 0, 0, 0, 0);
        initialize(bob, fixedRate, 5 * MINIMUM_SHARE_RESERVES);

        // Alice adds liquidity.
        addLiquidity(alice, initialLiquidity);

        // Open a max short position.
        uint256 shortSize = hyperdrive.calculateMaxShort();
        openShort(bob, shortSize);

        // One term passes and shorts mature.
        advanceTime(POSITION_DURATION, 0);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);

        // A checkpoint is missed.
        advanceTime(CHECKPOINT_DURATION, 0);
        uint256 missedCheckpointTime = block.timestamp;
        uint256 weightedSpotPriceMissed = hyperdrive
            .getCheckpoint(missedCheckpointTime)
            .weightedSpotPrice;

        // The weighted spot price at the missed checkpoint
        // should be zero.
        assertEq(weightedSpotPriceMissed, 0);

        // Several checkpoints are minted.
        advanceTimeWithCheckpoints2(3 * CHECKPOINT_DURATION, 0);
        uint256 currentSpotPrice = HyperdriveUtils.calculateSpotPrice(
            hyperdrive
        );

        // Mint the missed checkpoint.
        hyperdrive.checkpoint(missedCheckpointTime, 0);
        uint256 weightedSpotPriceMinted = hyperdrive
            .getCheckpoint(missedCheckpointTime)
            .weightedSpotPrice;

        // The missed checkpoint has now been minted. The
        // weighted spot price should be equal to the current
        // spot price.
        assertEq(weightedSpotPriceMinted, currentSpotPrice);
    }

    function test_weighted_average_netted_positions() external {
        // Normalize the fuzz params.
        uint256 initialVaultSharePrice = 1e18;
        int256 variableInterest = 0.05e18;
        uint256 numTrades = 5;
        uint256 tradeSize = 1_000_000e18;
        _test_weighted_average_netted_positions(
            initialVaultSharePrice,
            variableInterest,
            tradeSize,
            numTrades
        );
    }

    function test_weighted_average_netted_positions_fuzz(
        uint256 initialVaultSharePrice,
        int256 variableInterest,
        uint256 tradeSize,
        uint256 numTrades
    ) external {
        // Normalize the fuzz params.
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            0.5e18,
            5e18
        );
        variableInterest = variableInterest.normalizeToRange(0e18, .5e18);
        numTrades = tradeSize.normalizeToRange(1, 5);
        tradeSize = tradeSize.normalizeToRange(1e18, 50_000_000e18 / numTrades);
        _test_weighted_average_netted_positions(
            initialVaultSharePrice,
            variableInterest,
            tradeSize,
            numTrades
        );
    }

    function _test_weighted_average_netted_positions(
        uint256 initialVaultSharePrice,
        int256 variableInterest,
        uint256 tradeSize,
        uint256 numTrades
    ) internal {
        // Initialize the market.
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Fast forward time and accrue interest.
        advanceTime(POSITION_DURATION, variableInterest);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);

        // Open a variety of netted positions.
        uint256[] memory longMaturityTimes = new uint256[](numTrades);
        uint256[] memory shortMaturityTimes = new uint256[](numTrades);
        uint256[] memory bondAmounts = new uint256[](numTrades);
        uint256 lowestPrice = HyperdriveUtils.calculateSpotPrice(hyperdrive);
        uint256 highestPrice = lowestPrice;
        for (uint256 i = 0; i < numTrades; i++) {
            // Open long position.
            uint256 basePaidLong = tradeSize;
            (uint256 maturityTimeLong, uint256 bondAmount) = openLong(
                bob,
                basePaidLong
            );
            longMaturityTimes[i] = maturityTimeLong;
            bondAmounts[i] = bondAmount;
            if (HyperdriveUtils.calculateSpotPrice(hyperdrive) < lowestPrice) {
                lowestPrice = HyperdriveUtils.calculateSpotPrice(hyperdrive);
            }

            // Open short position.
            (uint256 maturityTimeShort, ) = openShort(bob, bondAmount);
            shortMaturityTimes[i] = maturityTimeShort;
            if (HyperdriveUtils.calculateSpotPrice(hyperdrive) > highestPrice) {
                highestPrice = HyperdriveUtils.calculateSpotPrice(hyperdrive);
            }
        }
        uint256 weightedSpotPriceAfter = hyperdrive
            .getCheckpoint(HyperdriveUtils.latestCheckpoint(hyperdrive))
            .weightedSpotPrice;
        uint256 spotPrice = HyperdriveUtils.calculateSpotPrice(hyperdrive);

        // The weighted spot price should equal the existing spot price since
        // all the trades netted out
        assertApproxEqAbs(weightedSpotPriceAfter, spotPrice, 10 wei);

        // The weighted spot price should be greater than or equal to the
        // existing spot price.
        assertGe(highestPrice, weightedSpotPriceAfter);

        // The weighted spot price should be less than the  or equal to the
        // existing spot price.
        assertLe(lowestPrice, weightedSpotPriceAfter);

        // Fast forward time, create checkpoints and accrue interest.
        advanceTimeWithCheckpoints2(POSITION_DURATION, 0);

        // Close out all positions.
        for (uint256 i = 0; i < numTrades; i++) {
            closeShort(bob, shortMaturityTimes[i], bondAmounts[i]);
            closeLong(bob, longMaturityTimes[i], bondAmounts[i]);
        }
        weightedSpotPriceAfter = hyperdrive
            .getCheckpoint(HyperdriveUtils.latestCheckpoint(hyperdrive))
            .weightedSpotPrice;
        spotPrice = HyperdriveUtils.calculateSpotPrice(hyperdrive);

        // The weighted spot price should equal the existing spot price since
        // all the trades netted out
        assertEq(weightedSpotPriceAfter, spotPrice);

        // The weighted spot price should be greater than or equal to the
        // existing spot price.
        assertGe(highestPrice, weightedSpotPriceAfter);

        // The weighted spot price should be less than the  or equal to the
        // existing spot price.
        assertLe(lowestPrice, weightedSpotPriceAfter);
    }
}
