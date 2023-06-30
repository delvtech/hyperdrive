// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract NegativeInterestTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function test_negative_interest_long_immediate_open_close_fuzz(
        uint256 initialSharePrice,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialSharePrice [0.1,10]
        // variableInterest [-100,0]
        initialSharePrice = initialSharePrice.normalizeToRange(.1e18, 10e18);
        variableInterest = -variableInterest.normalizeToRange(0, 1e18);
        test_negative_interest_long_immediate_open_close(
            initialSharePrice,
            variableInterest
        );
    }

    function test_negative_interest_long_immediate_open_close() external {
        // This tests the following scenario:
        // - initial_share_price > 1
        // - negative interest causes the share price to go down
        // - a long is opened and immediately closed
        {
            uint256 initialSharePrice = 1.5e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_long_immediate_open_close(
                initialSharePrice,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_share_price = 1
        // - negative interest causes the share price to go to < 1
        // - a long is opened and immediately closed
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_long_immediate_open_close(
                initialSharePrice,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_share_price < 1
        // - negative interest causes the share price to go to further < 1
        // - a long is opened and immediately closed
        {
            uint256 initialSharePrice = 0.95e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_long_immediate_open_close(
                initialSharePrice,
                variableInterest
            );
        }
    }

    function test_negative_interest_long_immediate_open_close(
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

        // Open a long position.
        uint256 basePaid = 10_000e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Immediately close the long.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // It shouldn't be profitable to open and close a long position with negative interest.
        assertGe(basePaid, baseProceeds);
        assertApproxEqAbs(baseProceeds, basePaid, 1e12);
    }

    function test_negative_interest_long_full_term_fuzz(
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
        test_negative_interest_long_full_term(
            initialSharePrice,
            preTradeVariableInterest,
            variableInterest
        );
    }

    function test_negative_interest_long_full_term() external {
        // This tests the following scenario:
        // - initial_share_price > 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the full term
        // - long is closed
        {
            uint256 initialSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_long_full_term(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_share_price = 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the full term
        // - long is closed
        {
            uint256 initialSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_long_full_term(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_share_price < 1
        // - negative interest causes the share price to go further down
        // - a long is opened
        // - negative interest accrues over the full term
        // - long is closed
        {
            uint256 initialSharePrice = 0.95e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_long_full_term(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }
    }

    function test_negative_interest_long_full_term(
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

        // Open a long position.
        uint256 basePaid = 10_000e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Full term passes
        advanceTime(POSITION_DURATION, variableInterest);

        // Close the long.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // We calculate the expected loss from the bonds bc the long still matures 1:1.
        (uint256 expectedProceeds, ) = HyperdriveUtils
            .calculateCompoundInterest(
                bondAmount,
                variableInterest,
                POSITION_DURATION
            );
        assertApproxEqAbs(baseProceeds, expectedProceeds, 1e6);
    }

    function test_negative_interest_long_half_term_fuzz(
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
        test_negative_interest_long_half_term(
            initialSharePrice,
            preTradeVariableInterest,
            variableInterest
        );
    }

    function test_negative_interest_long_half_term() external {
        // This tests the following scenario:
        // - initial_share_price > 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over half term
        // - long is closed
        {
            uint256 initialSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_long_half_term(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_share_price = 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over half term
        // - long is closed
        {
            uint256 initialSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_long_half_term(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }

        // This tests the following scenario:
        // - initial_share_price < 1
        // - negative interest causes the share price to go further down
        // - a long is opened
        // - negative interest accrues over half term
        // - long is closed
        {
            uint256 initialSharePrice = 0.90e18;
            int256 preTradeVariableInterest = -0.10e18;
            int256 variableInterest = -0.05e18;
            test_negative_interest_long_half_term(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest
            );
        }
    }

    function test_negative_interest_long_half_term(
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

        // Open a long position.
        uint256 basePaid = 10_000e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // half term passes
        advanceTime(POSITION_DURATION / 2, variableInterest);

        // Close the long.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Half the bonds mature 1:1
        (, int256 interest) = HyperdriveUtils.calculateCompoundInterest(
            basePaid,
            variableInterest,
            POSITION_DURATION / 2
        );
        uint256 expectedProceeds = bondAmount / 2 - uint256(-interest);

        // The other half are sold at the market rate
        expectedProceeds += basePaid / 2;

        // The expected proceeds overestimate the actual proceeds
        assertGe(expectedProceeds, baseProceeds);
    }
}
