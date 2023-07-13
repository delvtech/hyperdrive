// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { MockHyperdrive, IMockHyperdrive } from "../../mocks/MockHyperdrive.sol";
import { Lib } from "../../utils/Lib.sol";

contract NegativeInterestShortFeeTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function test_negative_interest_short_immediate_open_close_fees_fuzz(
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
        test_negative_interest_short_immediate_open_close_fees(
            initialSharePrice,
            variableInterest,
            curveFee,
            flatFee,
            governanceFee
        );
    }

    function test_negative_interest_short_immediate_open_close_fees() external {
        // This tests the following scenario:
        // - initial_share_price > 1
        // - negative interest causes the share price to go down
        // - a short is opened and immediately closed
        // - set the curve fee and governance fee to 100% to make the test easier to verify
        {
            uint256 initialSharePrice = 1.5e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 1e18;
            uint256 flatFee = 0.000e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_immediate_open_close_fees(
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
        // - a short is opened and immediately closed
        // - set the curve fee and governance fee to 100% to make the test easier to verify
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 1e18;
            uint256 flatFee = 0.000e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_immediate_open_close_fees(
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
        // - a short is opened and immediately closed
        // - set the curve fee and governance fee to 100% to make the test easier to verify
        {
            uint256 initialSharePrice = 0.95e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 1e18;
            uint256 flatFee = 0.000e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_immediate_open_close_fees(
                initialSharePrice,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }
    }

    function test_negative_interest_short_immediate_open_close_fees(
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
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        uint256 sharePrice = poolInfo.sharePrice;

        // Ensure that the governance initially has zero balance
        uint256 governanceBalanceBefore = baseToken.balanceOf(feeCollector);
        assertEq(governanceBalanceBefore, 0);

        // Ensure that fees are initially zero.
        {
            uint256 governanceFeesBeforeOpenShort = IMockHyperdrive(
                address(hyperdrive)
            ).getGovernanceFeesAccrued();
            assertEq(governanceFeesBeforeOpenShort, 0);
        }

        // Open a short position.
        uint256 shortAmount = 1e18;
        uint256 calculatedSpotPrice = HyperdriveUtils.calculateSpotPrice(
            hyperdrive
        );
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // Get the fees accrued from opening the short.
        uint256 governanceFeesAfterOpenShort = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();

        // Calculate the expected fees from opening the short
        uint256 expectedGovernanceFees = expectedOpenShortFees(
            shortAmount,
            HyperdriveUtils.calculateTimeRemaining(hyperdrive, maturityTime),
            calculatedSpotPrice,
            sharePrice,
            1e18,
            0,
            1e18
        );
        assertEq(governanceFeesAfterOpenShort, expectedGovernanceFees);

        // Close the short.
        calculatedSpotPrice = HyperdriveUtils.calculateSpotPrice(hyperdrive);
        closeShort(bob, maturityTime, shortAmount);

        // Get the fees accrued from closing the short.
        uint256 governanceFeesAfterCloseShort = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued() - governanceFeesAfterOpenShort;

        // Calculate the expected fees from closing the short
        expectedGovernanceFees = expectedCloseShortFees(
            shortAmount,
            HyperdriveUtils.calculateTimeRemaining(hyperdrive, maturityTime),
            calculatedSpotPrice,
            sharePrice,
            1e18,
            0,
            1e18
        );
        assertApproxEqAbs(
            governanceFeesAfterCloseShort,
            expectedGovernanceFees,
            1
        );
    }

    function test_negative_interest_short_full_term_fees_fuzz(
        uint256 initialSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialSharePrice [0.5,10]
        // variableInterest [-50,0]
        initialSharePrice = initialSharePrice.normalizeToRange(.5e18, 10e18);
        preTradeVariableInterest = -preTradeVariableInterest.normalizeToRange(
            0,
            .5e18
        );
        variableInterest = -variableInterest.normalizeToRange(0, .5e18);
        uint256 curveFee = 0e18;
        uint256 flatFee = 0.1e18;
        uint256 governanceFee = 1e18;
        test_negative_interest_short_full_term_fees(
            initialSharePrice,
            preTradeVariableInterest,
            variableInterest,
            curveFee,
            flatFee,
            governanceFee
        );
    }

    function test_negative_interest_short_full_term_fees() external {
        // This tests the following scenario:
        // - initial_share_price > 1
        // - negative interest causes the share price to go down
        // - a short is opened
        // - negative interest accrues over the full term
        // - short is closed
        // - set the flat fee to 10% and governance fee to 100% to make the test easier to verify
        {
            uint256 initialSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_full_term_fees(
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
        // - a short is opened
        // - negative interest accrues over the full term
        // - short is closed
        // - set the flat fee to 10% and governance fee to 100% to make the test easier to verify
        {
            uint256 initialSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_full_term_fees(
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
        // - a short is opened
        // - negative interest accrues over the full term
        // - short is closed
        // - set the flat fee to 10% and governance fee to 100% to make the test easier to verify
        {
            uint256 initialSharePrice = 0.95e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_full_term_fees(
                initialSharePrice,
                preTradeVariableInterest,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }
    }

    function test_negative_interest_short_full_term_fees(
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

        // Ensure that the governance initially has zero balance
        uint256 governanceBalanceBefore = baseToken.balanceOf(feeCollector);
        assertEq(governanceBalanceBefore, 0);

        // Ensure that fees are initially zero.
        uint256 governanceFeesBeforeOpenShort = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertEq(governanceFeesBeforeOpenShort, 0);

        // Open a short position.
        uint256 shortAmount = 1e18;
        uint256 calculatedSpotPrice = HyperdriveUtils.calculateSpotPrice(
            hyperdrive
        );
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // Fees are going to be 0 because this test uses 0% curve fee
        {
            // Get the fees accrued from opening the short.
            uint256 governanceFeesAfterOpenShort = IMockHyperdrive(
                address(hyperdrive)
            ).getGovernanceFeesAccrued();
            uint256 expectedGovernanceFees = 0;
            assertEq(governanceFeesAfterOpenShort, expectedGovernanceFees);
        }

        // Term matures and accrues interest
        advanceTime(POSITION_DURATION, variableInterest);

        // Record the closeSharePrice after interest accrual.
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        uint256 closeSharePrice = poolInfo.sharePrice;

        // Close the short.
        calculatedSpotPrice = HyperdriveUtils.calculateSpotPrice(hyperdrive);
        closeShort(bob, maturityTime, shortAmount);
        {
            // Get the fees accrued from closing the short.
            uint256 governanceFeesAfterCloseShort = IMockHyperdrive(
                address(hyperdrive)
            ).getGovernanceFeesAccrued();

            // Calculate the expected accrued fees from closing the short
            uint256 expectedFees = expectedCloseShortFees(
                shortAmount,
                HyperdriveUtils.calculateTimeRemaining(
                    hyperdrive,
                    maturityTime
                ),
                calculatedSpotPrice,
                closeSharePrice,
                0,
                .1e18,
                1e18
            );
            assertEq(governanceFeesAfterCloseShort, expectedFees);
        }
    }

    function test_negative_interest_short_half_term_fees_fuzz(
        uint256 initialSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialSharePrice [0.5,10]
        // variableInterest [-50,0]
        initialSharePrice = initialSharePrice.normalizeToRange(.5e18, 10e18);
        preTradeVariableInterest = -preTradeVariableInterest.normalizeToRange(
            0,
            .5e18
        );
        variableInterest = -variableInterest.normalizeToRange(0, .5e18);
        uint256 curveFee = 0.1e18;
        uint256 flatFee = 0.1e18;
        uint256 governanceFee = 1e18;
        test_negative_interest_short_half_term_fees(
            initialSharePrice,
            preTradeVariableInterest,
            variableInterest,
            curveFee,
            flatFee,
            governanceFee
        );
    }

    function test_negative_interest_short_half_term_fees() external {
        // This tests the following scenario:
        // - initial_share_price > 1
        // - negative interest causes the share price to go down
        // - a short is opened
        // - negative interest accrues over the half the term
        // - short is closed
        // - set the flat fee to 10%, curve fee to 10% and governance fee to 100% to make the test easier to verify
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_half_term_fees(
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
        // - a short is opened
        // - negative interest accrues over the half the term
        // - short is closed
        // - set the flat fee to 10%, curve fee to 10% and governance fee to 100% to make the test easier to verify
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_half_term_fees(
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
        // - a short is opened
        // - negative interest accrues over the half the term
        // - short is closed
        // - set the flat fee to 10%, curve fee to 10% and governance fee to 100% to make the test easier to verify
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 0.95e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_half_term_fees(
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

    function test_negative_interest_short_half_term_fees(
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
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        uint256 openSharePrice = poolInfo.sharePrice;
        {
            // Ensure that the governance initially has zero balance
            uint256 governanceBalanceBefore = baseToken.balanceOf(feeCollector);
            assertEq(governanceBalanceBefore, 0);
            // Ensure that fees are initially zero.
            uint256 governanceFeesBeforeOpenShort = IMockHyperdrive(
                address(hyperdrive)
            ).getGovernanceFeesAccrued();
            assertEq(governanceFeesBeforeOpenShort, 0);
        }

        // Open a short position.
        uint256 shortAmount = 1e18;
        uint256 calculatedSpotPrice = HyperdriveUtils.calculateSpotPrice(
            hyperdrive
        );
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // Get the fees accrued from opening the short.
        uint256 governanceFeesAfterOpenShort = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();

        // Calculate the expected accrued fees from opening the short and compare to the actual.
        {
            uint256 expectedGovernanceFees = expectedOpenShortFees(
                shortAmount,
                HyperdriveUtils.calculateTimeRemaining(
                    hyperdrive,
                    maturityTime
                ),
                calculatedSpotPrice,
                openSharePrice,
                .1e18,
                .1e18,
                1e18
            );
            assertEq(governanceFeesAfterOpenShort, expectedGovernanceFees);
        }

        // 1/2 term matures and accrues interest
        advanceTime(POSITION_DURATION / 2, variableInterest);

        // Record the closeSharePrice after interest accrual.
        poolInfo = hyperdrive.getPoolInfo();
        uint256 closeSharePrice = poolInfo.sharePrice;

        // Close the short.
        calculatedSpotPrice = HyperdriveUtils.calculateSpotPrice(hyperdrive);
        closeShort(bob, maturityTime, shortAmount);
        {
            // Get the fees after closing the short.
            uint256 governanceFeesAfterCloseShort = IMockHyperdrive(
                address(hyperdrive)
            ).getGovernanceFeesAccrued() - governanceFeesAfterOpenShort;

            // Calculate the flat and curve fees and compare then to the actual fees
            uint256 expectedFees = expectedCloseShortFees(
                shortAmount,
                HyperdriveUtils.calculateTimeRemaining(
                    hyperdrive,
                    maturityTime
                ),
                calculatedSpotPrice,
                closeSharePrice,
                .1e18,
                .1e18,
                1e18
            );
            assertEq(governanceFeesAfterCloseShort, expectedFees);
        }
    }

    function expectedOpenShortFees(
        uint256 bondAmount,
        uint256 normalizedTimeRemaining,
        uint256 calculatedSpotPrice,
        uint256 sharePrice,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceFee
    ) internal pure returns (uint256) {
        uint256 totalCurveFee = (FixedPointMath.ONE_18.sub(calculatedSpotPrice))
            .mulDown(curveFee)
            .mulDown(bondAmount)
            .mulDivDown(normalizedTimeRemaining, sharePrice);
        uint256 totalGovernanceFee = totalCurveFee.mulDown(governanceFee);
        uint256 flat = bondAmount.mulDivDown(
            FixedPointMath.ONE_18.sub(normalizedTimeRemaining),
            sharePrice
        );
        uint256 totalFlatFee = (flat.mulDown(flatFee));
        totalGovernanceFee += totalFlatFee.mulDown(governanceFee);
        return totalGovernanceFee;
    }

    function expectedCloseShortFees(
        uint256 bondAmount,
        uint256 normalizedTimeRemaining,
        uint256 calculatedSpotPrice,
        uint256 sharePrice,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceFee
    ) internal pure returns (uint256) {
        uint256 totalCurveFee = FixedPointMath.ONE_18.sub(calculatedSpotPrice);
        totalCurveFee = totalCurveFee
            .mulDown(curveFee)
            .mulDown(bondAmount)
            .mulDivDown(normalizedTimeRemaining, sharePrice);
        uint256 totalGovernanceFee = totalCurveFee.mulDown(governanceFee);
        uint256 flat = bondAmount.mulDivDown(
            FixedPointMath.ONE_18.sub(normalizedTimeRemaining),
            sharePrice
        );
        uint256 totalFlatFee = (flat.mulDown(flatFee));
        totalGovernanceFee += totalFlatFee.mulDown(governanceFee);
        return totalGovernanceFee;
    }
}
