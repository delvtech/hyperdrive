// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

import "forge-std/console2.sol";

// TODO: We need to test several cases for long negative interest.
//
// - [ ] Negative interest leading to haircut.
// - [ ] Negative interest leading to partial haircut.
// - [ ] Positive interest accrual, then long, then negative interest.
// - [ ] Long, negative interest, then positive interest after close.
// - [ ] Extreme inputs
//
// Ultimately, we'll want to test these cases with withdraw shares as well
// as this will complicate the issue.
contract NegativeInterestTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function test_negative_interest_short_complete_loss(
        int64 preTradingVariableRate,
        int64 postTradingApr
    ) external {
        // Initialize the market.
        uint256 apr = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Interest accrues for a term.
        vm.assume(
            preTradingVariableRate >= -0.9e18 && preTradingVariableRate <= 1e18
        );
        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a short.
        uint256 shortAmount = 10_000e18;
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // A small amount of negative interest accrues over the term.
        advanceTime(POSITION_DURATION, -0.01e18);

        // A checkpoint is created to lock in the close price.
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // Interest accrues for a term.
        vm.assume(postTradingApr >= -1e18 && postTradingApr <= 1e18);
        advanceTime(POSITION_DURATION, postTradingApr);

        // Bob closes the short. He should receive nothing on account of the
        // negative interest.
        uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount);
        assertEq(baseProceeds, 0);
    }

    function test_negative_interest_short_trading_profits(
        int64 preTradingVariableRate
    ) external {
        // Initialize the market with a very low APR.
        uint256 apr = 0.01e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Interest accrues for a term.
        vm.assume(
            preTradingVariableRate >= -0.5e18 && preTradingVariableRate <= 1e18
        );

        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a short.
        uint256 shortAmount = 10_000e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Celine opens a large short.
        uint256 longAmount = 300_000_000e18;
        openShort(celine, longAmount);

        // A small amount of negative interest accrues over the term.
        uint256 timeDelta = POSITION_DURATION.mulDown(0.5e18);
        int256 variableRate = -0.01e18;
        advanceTime(timeDelta, variableRate);

        // Bob closes the short. He should make a trading profit despite the
        // negative interest.
        uint256 estimatedProceeds = estimateShortProceeds(
            shortAmount,
            variableRate,
            HyperdriveUtils.calculateTimeRemaining(hyperdrive, maturityTime),
            timeDelta
        );
        uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount);
        assertGt(baseProceeds, basePaid);
        assertApproxEqAbs(baseProceeds, estimatedProceeds, 1e5);
    }

    function test_negative_interest_short_immediate_open_close_fuzz(
        uint256 initialSharePrice,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialSharePrice [0.1,10]
        // variableInterest [-100,0]
        initialSharePrice = initialSharePrice.normalizeToRange(.1e18, 10e18);
        variableInterest = -variableInterest.normalizeToRange(0, 1e18);
        test_negative_interest_short_immediate_open_close(
            initialSharePrice,
            variableInterest
        );
    }

    function test_negative_interest_short_immediate_open_close() external {
        // This tests the following scenario:
        // - initial_share_price > 1
        // - negative interest causes the share price to go down
        // - a short is opened and immediately closed
        {
            uint256 initialSharePrice = 1.5e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_short_immediate_open_close(
                initialSharePrice,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_share_price = 1
        // - negative interest causes the share price to go to < 1
        // - a short is opened and immediately closed
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_short_immediate_open_close(
                initialSharePrice,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_share_price < 1
        // - negative interest causes the share price to go to further < 1
        // - a short is opened and immediately closed
        {
            uint256 initialSharePrice = 0.95e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_short_immediate_open_close(
                initialSharePrice,
                variableInterest
            );
        }
    }

    function test_negative_interest_short_immediate_open_close(
        uint256 initialSharePrice,
        int256 variableInterest
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        // Open a short position.
        uint256 shortAmount = 10_000e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Calculate the estimated proceeds.
        uint256 estimatedProceeds = estimateShortProceeds(
            shortAmount,
            variableInterest,
            HyperdriveUtils.calculateTimeRemaining(hyperdrive, maturityTime),
            0
        );

        // Immediately close the short position.
        uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount);

        // It shouldn't be profitable to open and close a short position immediately with negative interest
        assertGe(basePaid, baseProceeds);
        assertApproxEqAbs(baseProceeds, estimatedProceeds, 1e7);
    }

    function test_negative_interest_short_full_term_fuzz(
        uint256 initialSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialSharePrice [0.1,10]
        // preTradeVariableInterest [-100,0]
        // variableInterest [-100,0]
        initialSharePrice = initialSharePrice.normalizeToRange(.1e18, 10e18);
        preTradeVariableInterest = -preTradeVariableInterest.normalizeToRange(
            0,
            1e18
        );
        variableInterest = -variableInterest.normalizeToRange(0, 1e18);
        console2.log("initialSharePrice: %s", initialSharePrice.toString(18));
        console2.log("preTradeVariableInterest: %s", preTradeVariableInterest.toString(18));
        console2.log("variableInterest: %s", variableInterest.toString(18));
        test_negative_interest_short_full_term(
            initialSharePrice,
            preTradeVariableInterest,
            variableInterest
        );
    }

    function test_negative_interest_short_full_term() external {
        // This tests the following scenario:
        // - initial_share_price > 1
        // - negative interest causes the share price to go down
        // - a short is opened
        // - negative interest accrues over the full term
        // - short is closed
        {
            uint256 initialSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_short_full_term(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_share_price = 1
        // - negative interest causes the share price to go down
        // - a short is opened
        // - negative interest accrues over the full term
        // - short is closed
        {
            uint256 initialSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_short_full_term(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_share_price < 1
        // - negative interest causes the share price to go further down
        // - a short is opened
        // - negative interest accrues over the full term
        // - short is closed
        {
            uint256 initialSharePrice = 0.95e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_short_full_term(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }
    }

    function test_negative_interest_short_full_term(
        uint256 initialSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue negative interest
        advanceTime(POSITION_DURATION, preTradeVariableInterest);

        // Open a short position.
        uint256 shortAmount = 10_000e18;
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // Full term passes
        advanceTime(POSITION_DURATION, variableInterest);

        // Calculate the estimated proceeds.
        uint256 estimatedProceeds = estimateShortProceeds(
            shortAmount,
            variableInterest,
            HyperdriveUtils.calculateTimeRemaining(hyperdrive, maturityTime),
            POSITION_DURATION
        );

        // Close the short.
        uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount);
        assertApproxEqAbs(baseProceeds, estimatedProceeds, 10);
    }

    function estimateShortProceeds(
        uint256 shortAmount,
        int256 variableRate,
        uint256 normalizedTimeRemaining,
        uint256 timeElapsed
    ) internal view returns (uint256) {
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = hyperdrive.getPoolConfig();

        (, , uint256 expectedSharePayment) = HyperdriveMath.calculateCloseShort(
            poolInfo.shareReserves,
            poolInfo.bondReserves,
            shortAmount,
            normalizedTimeRemaining,
            poolConfig.timeStretch,
            poolInfo.sharePrice,
            poolConfig.initialSharePrice
        );
        console2.log("shortAmount", shortAmount.toString(18));
        console2.log(
            "expectedSharePayment",
            expectedSharePayment.toString(18));

        (, int256 expectedInterest) = HyperdriveUtils.calculateCompoundInterest(
            shortAmount,
            variableRate,
            timeElapsed
        );
        console2.log(
            "sharePrice", poolInfo.sharePrice.toString(18)
        );
        console2.log("poolInfo.sharePrice.mulDown(expectedSharePayment)",poolInfo.sharePrice.mulDown(expectedSharePayment).toString(18));
        console2.log(
            "expectedInterest",
            expectedInterest.toString(18));
        int256 delta = int256(shortAmount - poolInfo.sharePrice.mulDown(expectedSharePayment));
        if ( delta + expectedInterest > 0 ) {
            return uint256(delta + expectedInterest);
        } else {
            return 0;
        }
    }
}
