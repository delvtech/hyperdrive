// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { MockHyperdrive, IMockHyperdrive } from "../../../contracts/test/MockHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract NegativeInterestLongFeeTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function test_negative_interest_long_immediate_open_close_fees_fuzz(
        uint256 initialVaultSharePrice,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialVaultSharePrice [0.5,10]
        // variableInterest [-50,0]
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            .5e18,
            10e18
        );
        variableInterest = -variableInterest.normalizeToRange(0, .5e18);
        uint256 curveFee = 0.1e18;
        uint256 flatFee = 0.000e18;
        uint256 governanceFee = 1e18;
        test_negative_interest_long_immediate_open_close_fees(
            initialVaultSharePrice,
            variableInterest,
            curveFee,
            flatFee,
            governanceFee
        );
    }

    function test_negative_interest_long_immediate_open_close_fees() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - negative interest causes the share price to go down
        // - a long is opened and immediately closed
        // - set the curve fee to 10% and the governance fee to 100% to make the
        //   test easier to verify
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_immediate_open_close_fees(
                initialVaultSharePrice,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - negative interest causes the share price to go down
        // - a long is opened and immediately closed
        // - set the curve fee to 10% and the governance fee to 100% to make the
        //   test easier to verify
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_immediate_open_close_fees(
                initialVaultSharePrice,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - negative interest causes the share price to go down
        // - a long is opened and immediately closed
        // - set the curve fee to 10% and the governance fee to 100% to make the
        //   test easier to verify
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_immediate_open_close_fees(
                initialVaultSharePrice,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }
    }

    function test_negative_interest_long_immediate_open_close_fees(
        uint256 initialVaultSharePrice,
        int256 variableInterest,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceFee
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(
            alice,
            apr,
            initialVaultSharePrice,
            curveFee,
            flatFee,
            governanceFee,
            0
        );
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        // Record the vaultSharePrice after interest accrual.
        (uint256 vaultSharePrice, ) = HyperdriveUtils.calculateCompoundInterest(
            initialVaultSharePrice,
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
                asBase: true,
                destination: bob,
                depositAmount: basePaid,
                minSharePrice: 0,
                minSlippage: 0, // TODO: This should never go below the base amount. Investigate this.
                maxSlippage: type(uint256).max,
                extraData: new bytes(0)
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
        uint256 curveFee_ = curveFee; // avoid stack too deep
        uint256 expectedGovernanceFees = curveFee_
            .mulDown(ONE.divDown(calculatedSpotPrice) - ONE)
            .mulDown(basePaid)
            .mulDivDown(calculatedSpotPrice, vaultSharePrice);
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
        expectedGovernanceFees = curveFee_
            .mulDown(ONE - calculatedSpotPrice)
            .mulDivDown(bondAmount, vaultSharePrice);
        assertApproxEqAbs(
            governanceFeesAfterCloseLong,
            expectedGovernanceFees,
            1e10
        );
    }

    function test_negative_interest_long_full_term_fees_fuzz(
        uint256 initialVaultSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialVaultSharePrice [0.5,10]
        // variableInterest [-50,0]
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            .5e18,
            10e18
        );
        preTradeVariableInterest = -preTradeVariableInterest.normalizeToRange(
            0,
            .5e18
        );
        variableInterest = -variableInterest.normalizeToRange(0, .5e18);
        uint256 curveFee = 0e18;
        uint256 flatFee = 0.01e18;
        uint256 governanceFee = 1e18;
        test_negative_interest_long_full_term_fees(
            initialVaultSharePrice,
            preTradeVariableInterest,
            variableInterest,
            curveFee,
            flatFee,
            governanceFee
        );
    }

    function test_negative_interest_long_full_term_fees() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the full term
        // - long is closed
        // - set the flat fee to 10% and governance fee to 100% to make the test easier to verify
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0e18;
            uint256 flatFee = 0.01e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_full_term_fees(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the full term
        // - long is closed
        // - set the flat fee to 10% and governance fee to 100% to make the test easier to verify
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0e18;
            uint256 flatFee = 0.01e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_full_term_fees(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the full term
        // - long is closed
        // - set the flat fee to 10% and governance fee to 100% to make the test easier to verify
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0e18;
            uint256 flatFee = 0.01e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_full_term_fees(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }
    }

    function test_negative_interest_long_full_term_fees(
        uint256 initialVaultSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceFee
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(
            alice,
            apr,
            initialVaultSharePrice,
            curveFee,
            flatFee,
            governanceFee,
            0
        );
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, preTradeVariableInterest);

        // Record the openVaultSharePrice after interest accrual.
        (uint256 openVaultSharePrice, ) = HyperdriveUtils
            .calculateCompoundInterest(
                initialVaultSharePrice,
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
                asBase: true,
                destination: bob,
                depositAmount: basePaid,
                minSharePrice: 0,
                minSlippage: 0, // TODO: This should never go below the base amount. Investigate this.
                maxSlippage: type(uint256).max,
                extraData: new bytes(0)
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

        // Close the long.
        closeLong(bob, maturityTime, bondAmount);
        {
            // Get the fees accrued from closing the long.
            uint256 governanceFeesAfterCloseLong = IMockHyperdrive(
                address(hyperdrive)
            ).getGovernanceFeesAccrued();
            // Calculate the expected accrued fees from closing the long. Let
            // `g` be the governance fee in base. Normally, `g / c` gives the
            // governance fee in shares, but negative interest accrued over the
            // period, so we scale the governance fee by `c / c_0` where `c_0`
            // is the share price at the beginning of the checkpoint. This gives
            // us a governance fee of `(c / c_0) * (g / c)  = g / c_0`.
            uint256 expectedGovernanceFees = (bondAmount * flatFee) /
                openVaultSharePrice;
            assertApproxEqAbs(
                governanceFeesAfterCloseLong,
                expectedGovernanceFees,
                10 wei
            );
        }
    }

    function test_negative_interest_long_half_term_fees_fuzz(
        uint256 initialVaultSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialVaultSharePrice [0.5,10]
        // variableInterest [-50,0]
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            .5e18,
            10e18
        );
        preTradeVariableInterest = -preTradeVariableInterest.normalizeToRange(
            0,
            .5e18
        );
        variableInterest = -variableInterest.normalizeToRange(0, .5e18);
        uint256 curveFee = 0.1e18;
        uint256 flatFee = 0.01e18;
        uint256 governanceFee = 1e18;
        test_negative_interest_long_half_term_fees(
            initialVaultSharePrice,
            preTradeVariableInterest,
            variableInterest,
            curveFee,
            flatFee,
            governanceFee
        );
    }

    function test_negative_interest_long_half_term_fees() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the half the term
        // - long is closed
        // - set the flat fee to 10%, curve fee to 10% and governance fee to 100% to make the test easier to verify
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0.01e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_half_term_fees(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_vault_share_price = 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the half the term
        // - long is closed
        // - set the flat fee to 10%, curve fee to 10% and governance fee to 100% to make the test easier to verify
        snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0.01e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_half_term_fees(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_vault_share_price < 1
        // - negative interest causes the share price to go down
        // - a long is opened
        // - negative interest accrues over the half the term
        // - long is closed
        // - set the flat fee to 10%, curve fee to 10% and governance fee to 100% to make the test easier to verify
        snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0.01e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_long_half_term_fees(
                initialVaultSharePrice,
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
        uint256 initialVaultSharePrice,
        int256 preTradeVariableInterest,
        int256 variableInterest,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceFee
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(
            alice,
            apr,
            initialVaultSharePrice,
            curveFee,
            flatFee,
            governanceFee,
            0
        );
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, preTradeVariableInterest);

        // Record the openVaultSharePrice after interest accrual.
        (uint256 openVaultSharePrice, ) = HyperdriveUtils
            .calculateCompoundInterest(
                initialVaultSharePrice,
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
                asBase: true,
                destination: bob,
                depositAmount: basePaid,
                minSharePrice: 0,
                minSlippage: 0, // TODO: This should never go below the base amount. Investigate this.
                maxSlippage: type(uint256).max,
                extraData: new bytes(0)
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
            uint256 expectedGovernanceFees = (ONE.divDown(calculatedSpotPrice) -
                ONE).mulDown(basePaid).mulDown(curveFee).mulDivDown(
                    calculatedSpotPrice,
                    openVaultSharePrice
                );
            assertApproxEqAbs(
                governanceFeesAfterOpenLong,
                expectedGovernanceFees,
                1e9
            );
        }

        // 1/2 term matures and accrues interest
        advanceTime(POSITION_DURATION / 2, variableInterest);

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
                .mulDivDown(ONE - normalizedTimeRemaining, openVaultSharePrice)
                .mulDown(flatFee);
            uint256 expectedCurve = (ONE - calculatedSpotPrice)
                .mulDown(0.1e18)
                .mulDown(bondAmount)
                .mulDivDown(normalizedTimeRemaining, openVaultSharePrice);
            assertApproxEqAbs(
                governanceFeesAfterCloseLong,
                (expectedFlat + expectedCurve),
                10 wei
            );
        }
    }
}
