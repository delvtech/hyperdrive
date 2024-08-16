// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract VariableInterestShortTest is HyperdriveTest {
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
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);

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
        uint256 longAmount = 100_000_000e18;
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

    function test_positive_negative_interest_short_immediate_open_close_fuzz(
        uint256 initialVaultSharePrice,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialVaultSharePrice [0.1,5]
        // variableInterest [-50,50]
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            .1e18,
            5e18
        );
        variableInterest = variableInterest.normalizeToRange(-.5e18, .5e18);
        immediate_open_close(initialVaultSharePrice, variableInterest);
    }

    function test_positive_interest_short_immediate_open_close() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - positive interest causes the share price to go up
        // - a short is opened and immediately closed
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 variableInterest = 0.05e18;
            immediate_open_close(initialVaultSharePrice, variableInterest);
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go up
        // - a short is opened and immediately closed
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            immediate_open_close(initialVaultSharePrice, variableInterest);
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - positive interest causes the share price to go up
        // - a short is opened and immediately closed
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 variableInterest = 0.10e18;
            immediate_open_close(initialVaultSharePrice, variableInterest);
        }
    }

    function test_negative_interest_short_immediate_open_close() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - negative interest causes the share price to go down
        // - a short is opened and immediately closed
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 variableInterest = -0.05e18;
            immediate_open_close(initialVaultSharePrice, variableInterest);
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - negative interest causes the share price to go to < 1
        // - a short is opened and immediately closed
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = -0.05e18;
            immediate_open_close(initialVaultSharePrice, variableInterest);
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - negative interest causes the share price to go to further < 1
        // - a short is opened and immediately closed
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 variableInterest = -0.05e18;
            immediate_open_close(initialVaultSharePrice, variableInterest);
        }
    }

    function immediate_open_close(
        uint256 initialVaultSharePrice,
        int256 variableInterest
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        // Open a short position.
        uint256 shortAmount = 10_000e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Immediately close the short position.
        uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount);

        // It shouldn't be profitable to open and close a short position immediately
        assertGe(basePaid, baseProceeds);
        assertApproxEqAbs(baseProceeds, basePaid, 1e11); // NOTE: This error grows with initialVaultSharePrice and variableInterest
    }

    function test_positive_negative_interest_short_full_term_fuzz(
        uint256 initialVaultSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialVaultSharePrice [0.1,5]
        // preTradeVariableInterest [-50,50]
        // variableInterest [-50,50]
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            .1e18,
            5e18
        );
        preTradeVariableInterest = preTradeVariableInterest.normalizeToRange(
            -0.5e18,
            0.5e18
        );
        variableInterest = variableInterest.normalizeToRange(-0.5e18, 0.5e18);
        full_term(
            initialVaultSharePrice,
            preTradeVariableInterest,
            variableInterest
        );
    }

    function test_positive_interest_short_full_term() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - positive interest causes the share price to go up
        // - a short is opened
        // - positive interest accrues over the full term
        // - short is closed
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 preTradeVariableInterest = 0.10e18;
            int256 variableInterest = 0.05e18;
            full_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive interest causes the share price to go up
        // - a short is opened
        // - positive interest accrues over the full term
        // - short is closed
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 preTradeVariableInterest = 0.10e18;
            int256 variableInterest = 0.05e18;
            full_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - positive interest causes the share price to go up
        // - a short is opened
        // - positive interest accrues over the full term
        // - short is closed
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 preTradeVariableInterest = 0.10e18;
            int256 variableInterest = 0.05e18;
            full_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }
    }

    function test_negative_interest_short_full_term() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - negative interest causes the share price to go down
        // - a short is opened
        // - negative interest accrues over the full term
        // - short is closed
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            uint256 baseProceeds = full_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
            // Because variable interest is negative, the short position earns nothing
            assertApproxEqAbs(baseProceeds, 0, 10);
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - negative interest causes the share price to go down
        // - a short is opened
        // - negative interest accrues over the full term
        // - short is closed
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            uint256 baseProceeds = full_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
            // Because variable interest is negative, the short position earns nothing
            assertApproxEqAbs(baseProceeds, 0, 10);
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - negative interest causes the share price to go further down
        // - a short is opened
        // - negative interest accrues over the full term
        // - short is closed
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            uint256 baseProceeds = full_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
            // Because variable interest is negative, the short position earns nothing
            assertApproxEqAbs(baseProceeds, 0, 10);
        }
    }

    function full_term(
        uint256 initialVaultSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) internal returns (uint256) {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
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
        assertApproxEqAbs(baseProceeds, estimatedProceeds, 1e7);
        return baseProceeds;
    }

    function test_positive_negative_interest_short_half_term_fuzz(
        uint256 initialVaultSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialVaultSharePrice [0.1,5]
        // preTradeVariableInterest [-50,50]
        // variableInterest [-50,50]
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            .1e18,
            10e18
        );
        preTradeVariableInterest = preTradeVariableInterest.normalizeToRange(
            -0.5e18,
            0.5e18
        );
        variableInterest = variableInterest.normalizeToRange(-0.5e18, 0.5e18);
        half_term(
            initialVaultSharePrice,
            preTradeVariableInterest,
            variableInterest
        );
    }

    function test_positive_interest_short_half_term() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - positive interest causes the share price to go up
        // - a short is opened
        // - positive interest accrues over half term
        // - short is closed
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 preTradeVariableInterest = 0.10e18;
            int256 variableInterest = 0.05e18;
            half_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - positive  interest causes the share price to go up
        // - a short is opened
        // - positive interest accrues over half term
        // - short is closed
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 preTradeVariableInterest = 0.10e18;
            int256 variableInterest = 0.05e18;
            half_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - positive interest causes the share price to go further down
        // - a short is opened
        // - positive interest accrues over half term
        // - short is closed
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 preTradeVariableInterest = 0.10e18;
            int256 variableInterest = 0.05e18;
            half_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }
    }

    function test_negative_interest_short_half_term() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - negative interest causes the share price to go down
        // - a short is opened
        // - negative interest accrues over half term
        // - short is closed
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            half_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - negative interest causes the share price to go down
        // - a short is opened
        // - negative interest accrues over half term
        // - short is closed
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            half_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - negative interest causes the share price to go further down
        // - a short is opened
        // - negative interest accrues over half term
        // - short is closed
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            half_term(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }
    }

    function half_term(
        uint256 initialVaultSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialVaultSharePrice, 0, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue negative interest
        advanceTime(POSITION_DURATION, preTradeVariableInterest);

        // Open a short position.
        uint256 shortAmount = 10_000e18;
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // half term passes
        advanceTime(POSITION_DURATION / 2, variableInterest);

        // Calculate the estimated proceeds.
        uint256 estimatedProceeds = estimateShortProceeds(
            shortAmount,
            variableInterest,
            HyperdriveUtils.calculateTimeRemaining(hyperdrive, maturityTime),
            POSITION_DURATION / 2
        );

        // Close the short.
        uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount);
        assertApproxEqAbs(estimatedProceeds, baseProceeds, 1e7);
    }
}
