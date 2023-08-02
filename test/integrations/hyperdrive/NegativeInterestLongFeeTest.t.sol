// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { MockHyperdrive, IMockHyperdrive } from "../../mocks/MockHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract NegativeInterestLongFeeTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

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
        (uint256 maturityTime, uint256 bondAmount) = openLong(
            bob,
            basePaid,
            DepositOverrides({
                asUnderlying: true,
                depositAmount: basePaid,
                minSlippage: 0, // TODO: This should never go below the base amount. Investigate this.
                maxSlippage: type(uint256).max
            })
        );
        uint256 calculatedSpotPrice = HyperdriveUtils.calculateSpotPrice(
            hyperdrive
        );

        // Get the fees accrued from opening the long.
        uint256 governanceFeesAfterOpenLong = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();

        // Calculate the expected fees from opening the long
        uint256 expectedGovernanceFees = (
            FixedPointMath.ONE_18.divDown(calculatedSpotPrice)
        ).sub(FixedPointMath.ONE_18).mulDown(basePaid).mulDivDown(
                calculatedSpotPrice,
                sharePrice
            );
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
        expectedGovernanceFees = (
            FixedPointMath.ONE_18.divDown(calculatedSpotPrice)
        ).sub(FixedPointMath.ONE_18).mulDown(basePaid).mulDivDown(
                calculatedSpotPrice,
                sharePrice
            );

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
        preTradeVariableInterest = -preTradeVariableInterest.normalizeToRange(
            0,
            .5e18
        );
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
        (uint256 maturityTime, uint256 bondAmount) = openLong(
            bob,
            basePaid,
            DepositOverrides({
                asUnderlying: true,
                depositAmount: basePaid,
                minSlippage: 0, // TODO: This should never go below the base amount. Investigate this.
                maxSlippage: type(uint256).max
            })
        );

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
        preTradeVariableInterest = -preTradeVariableInterest.normalizeToRange(
            0,
            .5e18
        );
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
        (uint256 maturityTime, uint256 bondAmount) = openLong(
            bob,
            basePaid,
            DepositOverrides({
                asUnderlying: true,
                depositAmount: basePaid,
                minSlippage: 0, // TODO: This should never go below the base amount. Investigate this.
                maxSlippage: type(uint256).max
            })
        );
        uint256 calculatedSpotPrice = HyperdriveUtils.calculateSpotPrice(
            hyperdrive
        );

        // Get the fees accrued from opening the long.
        uint256 governanceFeesAfterOpenLong = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();

        // Calculate the expected accrued fees from opening the long and compare to the actual.
        {
            uint256 expectedGovernanceFees = (
                FixedPointMath.ONE_18.divDown(calculatedSpotPrice)
            )
                .sub(FixedPointMath.ONE_18)
                .mulDown(basePaid)
                .mulDown(curveFee)
                .mulDivDown(calculatedSpotPrice, openSharePrice);
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
}
