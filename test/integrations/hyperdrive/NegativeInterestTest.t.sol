// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { MockHyperdrive, IMockHyperdrive } from "../../mocks/MockHyperdrive.sol";
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
        // User loses less than 1000 gwei
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

    function test_negative_interest_long_half_term() external {
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
        // - negative interest accrues over the full term
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
        // - negative interest accrues over the full term
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

        // Full term passes
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

    function test_negative_interest_long_immediate_open_close_fees_fuzz(
        uint256 initialSharePrice,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialSharePrice [0.5,10]
        // variableInterest [-50,0]
        initialSharePrice = initialSharePrice.normalizeToRange(.5e18, 10e18);
        variableInterest = -variableInterest.normalizeToRange(0, .5e18);
        uint256 curveFee = 1e18;
        uint256 flatFee = 0.000e18;
        uint256 governanceFee = 1e18;
        test_negative_interest_long_immediate_open_close_fees(
            initialSharePrice,
            variableInterest,
            curveFee,
            flatFee,
            governanceFee
        );
    }

    function test_negative_interest_long_immediate_open_close_fees() external {
        // This tests the following scenario:
        // - initial_share_price > 1
        // - negative interest causes the share price to go down
        // - a long is opened and immediately closed
        // - set the curve fee and governance fee to 100% to make the test easier to verify
        {
            uint256 initialSharePrice = 1.5e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 1e18;
            uint256 flatFee = 0.000e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_immediate_open_close_fees(
                initialSharePrice,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }

        // This tests the following scenario:
        // - initial_share_price = 1
        // - negative interest causes the share price to go down
        // - a long is opened and immediately closed
        // - set the curve fee and governance fee to 100% to make the test easier to verify
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 1e18;
            uint256 flatFee = 0.000e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_immediate_open_close_fees(
                initialSharePrice,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }

        // This tests the following scenario:
        // - initial_share_price < 1
        // - negative interest causes the share price to go down
        // - a long is opened and immediately closed
        // - set the curve fee and governance fee to 100% to make the test easier to verify
        {
            uint256 initialSharePrice = 0.95e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 1e18;
            uint256 flatFee = 0.000e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_immediate_open_close_fees(
                initialSharePrice,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }
    }

    function test_negative_interest_long_immediate_open_close_fees(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceFee
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, curveFee, flatFee, governanceFee);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        // Record the sharePrice after interest accrual.

        (uint256 sharePrice, ) = HyperdriveUtils.calculateCompoundInterest(
            initialSharePrice,
            variableInterest,
            POSITION_DURATION
        );

        // Ensure that the governance initially has zero balance
        uint256 governanceBalanceBefore = baseToken.balanceOf(feeCollector);
        assertEq(governanceBalanceBefore, 0);

        // Ensure that fees are initially zero.
        {
            uint256 governanceFeesBeforeOpenLong = IMockHyperdrive(
                address(hyperdrive)
            ).getGovernanceFeesAccrued();
            assertEq(governanceFeesBeforeOpenLong, 0);
        }

        // Open a long position.
        uint256 basePaid = 1e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        uint256 calculatedSpotPrice = HyperdriveUtils.calculateSpotPrice(
            hyperdrive
        );

        // Get the fees accrued from opening the long.
        uint256 governanceFeesAfterOpenLong = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        // Calculate the expected fees from opening the long
        uint256 expectedGovernanceFees = (FixedPointMath.ONE_18.sub(calculatedSpotPrice)).mulDown(basePaid).mulDivDown(curveFee, sharePrice);
        assertApproxEqAbs(
            governanceFeesAfterOpenLong,
            expectedGovernanceFees,
            1e10
        );

        // Immediately close the long.
        closeLong(bob, maturityTime, bondAmount);
        // Get the fees accrued from closing the long.
        uint256 governanceFeesAfterCloseLong = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued() - governanceFeesAfterOpenLong;
        // Calculate the expected fees from closing the long
        expectedGovernanceFees = (FixedPointMath.ONE_18.sub(calculatedSpotPrice)).mulDown(basePaid).mulDivDown(curveFee, sharePrice);
        assertApproxEqAbs(
            governanceFeesAfterCloseLong,
            expectedGovernanceFees,
            1e10
        );
    }

    function test_negative_interest_long_full_term_fees_fuzz(
        uint256 initialSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialSharePrice [0.5,10]
        // variableInterest [-50,0]
        initialSharePrice = initialSharePrice.normalizeToRange(.5e18, 10e18);
        preTradeVariableInterest = -preTradeVariableInterest.normalizeToRange(0, .5e18);
        variableInterest = -variableInterest.normalizeToRange(0, .5e18);
        uint256 curveFee = 0e18;
        uint256 flatFee = 0.1e18;
        uint256 governanceFee = 1e18;
        test_negative_interest_long_full_term_fees(
            initialSharePrice,
            preTradeVariableInterest,
            variableInterest,
            curveFee,
            flatFee,
            governanceFee
        );
    }

    function test_negative_interest_long_full_term_fees() external {
        // This tests the following scenario:
        // - initial_share_price > 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the full term
        // - long is closed
        // - set the flat fee to 10% and governance fee to 100% to make the test easier to verify
        {
            uint256 initialSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_full_term_fees(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }

        // This tests the following scenario:
        // - initial_share_price = 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the full term
        // - long is closed
        // - set the flat fee to 10% and governance fee to 100% to make the test easier to verify
        {
            uint256 initialSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_full_term_fees(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }

        // This tests the following scenario:
        // - initial_share_price < 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the full term
        // - long is closed
        // - set the flat fee to 10% and governance fee to 100% to make the test easier to verify
        {
            uint256 initialSharePrice = 0.95e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_full_term_fees(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }
    }

    function test_negative_interest_long_full_term_fees(
        uint256 initialSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceFee
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, curveFee, flatFee, governanceFee);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, preTradeVariableInterest);

        // Record the openSharePrice after interest accrual.
        (uint256 openSharePrice, ) = HyperdriveUtils.calculateCompoundInterest(
            initialSharePrice,
            preTradeVariableInterest,
            POSITION_DURATION
        );

        // Ensure that the governance initially has zero balance
        uint256 governanceBalanceBefore = baseToken.balanceOf(feeCollector);
        assertEq(governanceBalanceBefore, 0);

        // Ensure that fees are initially zero.
        uint256 governanceFeesBeforeOpenLong = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertEq(governanceFeesBeforeOpenLong, 0);

        // Open a long position.
        uint256 basePaid = 1e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Fees are going to be 0 because this test uses 0% curve fee
        {
            // Get the fees accrued from opening the long.
            uint256 governanceFeesAfterOpenLong = IMockHyperdrive(
                address(hyperdrive)
            ).getGovernanceFeesAccrued();
            uint256 expectedGovernanceFees = 0;
            assertEq(governanceFeesAfterOpenLong, expectedGovernanceFees);
        }

        // Term matures and accrues interest
        advanceTime(POSITION_DURATION, variableInterest);

        // Record the closeSharePrice after interest accrual.
        (uint256 closeSharePrice, ) = HyperdriveUtils.calculateCompoundInterest(
            openSharePrice,
            variableInterest,
            POSITION_DURATION
        );

        // Close the long.
        closeLong(bob, maturityTime, bondAmount);
        {
            // Get the fees accrued from closing the long.
            uint256 governanceFeesAfterCloseLong = IMockHyperdrive(
                address(hyperdrive)
            ).getGovernanceFeesAccrued();
            // Calculate the expected accrued fees from closing the long
            uint256 expectedGovernanceFees = (bondAmount * flatFee) /
                closeSharePrice;
            assertApproxEqAbs(
                governanceFeesAfterCloseLong,
                expectedGovernanceFees,
                10 wei
            );
        }
    }

    function test_negative_interest_long_half_term_fees_fuzz(
        uint256 initialSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialSharePrice [0.5,10]
        // variableInterest [-50,0]
        initialSharePrice = initialSharePrice.normalizeToRange(.5e18, 10e18);
        preTradeVariableInterest = -preTradeVariableInterest.normalizeToRange(0, .5e18);
        variableInterest = -variableInterest.normalizeToRange(0, .5e18);
        uint256 curveFee = 0.1e18;
        uint256 flatFee = 0.1e18;
        uint256 governanceFee = 1e18;
        test_negative_interest_long_half_term_fees(
            initialSharePrice,
            preTradeVariableInterest,
            variableInterest,
            curveFee,
            flatFee,
            governanceFee
        );
    }

    function test_negative_interest_long_half_term_fees() external {
        // This tests the following scenario:
        // - initial_share_price > 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the half the term
        // - long is closed
        // - set the flat fee to 10%, curve fee to 10% and governance fee to 100% to make the test easier to verify
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_half_term_fees(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the half the term
        // - long is closed
        // - set the flat fee to 10%, curve fee to 10% and governance fee to 100% to make the test easier to verify
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_half_term_fees(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price < 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the half the term
        // - long is closed
        // - set the flat fee to 10%, curve fee to 10% and governance fee to 100% to make the test easier to verify
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 0.95e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_half_term_fees(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }
        vm.revertTo(snapshotId);
    }

    function test_negative_interest_long_half_term_fees(
        uint256 initialSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceFee
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, curveFee, flatFee, governanceFee);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, preTradeVariableInterest);

        // Record the openSharePrice after interest accrual.
        (uint256 openSharePrice, ) = HyperdriveUtils.calculateCompoundInterest(
            initialSharePrice,
            preTradeVariableInterest,
            POSITION_DURATION
        );

        {
            // Ensure that the governance initially has zero balance
            uint256 governanceBalanceBefore = baseToken.balanceOf(feeCollector);
            assertEq(governanceBalanceBefore, 0);
            // Ensure that fees are initially zero.
            uint256 governanceFeesBeforeOpenLong = IMockHyperdrive(
                address(hyperdrive)
            ).getGovernanceFeesAccrued();
            assertEq(governanceFeesBeforeOpenLong, 0);
        }

        // Open a long position.
        uint256 basePaid = 1e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        uint256 calculatedSpotPrice = HyperdriveUtils.calculateSpotPrice(
            hyperdrive
        );

        // Get the fees accrued from opening the long.
        uint256 governanceFeesAfterOpenLong = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();

        // Calculate the expected accrued fees from opening the long and compare to the actual.
        {
            // This is close enough
        uint256 expectedGovernanceFees = (FixedPointMath.ONE_18.sub(calculatedSpotPrice)).mulDown(basePaid).mulDivDown(curveFee, openSharePrice);

            assertApproxEqAbs(
                governanceFeesAfterOpenLong,
                expectedGovernanceFees,
                1e9
            );
        }

        // 1/2 term matures and accrues interest
        advanceTime(POSITION_DURATION / 2, variableInterest);

        // Record the closeSharePrice after interest accrual.
        (uint256 closeSharePrice, ) = HyperdriveUtils.calculateCompoundInterest(
            openSharePrice,
            variableInterest,
            POSITION_DURATION / 2
        );
        // Close the long.
        closeLong(bob, maturityTime, bondAmount);

        {
            // Get the fees after closing the long.
            uint256 governanceFeesAfterCloseLong = IMockHyperdrive(
                address(hyperdrive)
            ).getGovernanceFeesAccrued() - governanceFeesAfterOpenLong;

            // POSITION_DURATION/2 isn't exactly half a year so we use the exact value here
            uint256 normalizedTimeRemaining = 0.501369863013698630e18;

            // Calculate the flat and curve fees and compare then to the actual fees
            uint256 expectedFlat = bondAmount
                .mulDivDown(
                    FixedPointMath.ONE_18.sub(normalizedTimeRemaining),
                    closeSharePrice
                )
                .mulDown(0.1e18);
            uint256 expectedCurve = (
                FixedPointMath.ONE_18.sub(calculatedSpotPrice)
            ).mulDown(0.1e18).mulDown(bondAmount).mulDivDown(
                    normalizedTimeRemaining,
                    closeSharePrice
                );
            assertApproxEqAbs(
                governanceFeesAfterCloseLong,
                expectedFlat + expectedCurve,
                10 wei
            );
        }
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
        (, int256 expectedInterest) = HyperdriveUtils.calculateCompoundInterest(
            shortAmount,
            variableRate,
            timeElapsed
        );
        return
            uint256(
                int256(
                    shortAmount -
                        poolInfo.sharePrice.mulDown(expectedSharePayment)
                ) + expectedInterest
            );
    }
}
