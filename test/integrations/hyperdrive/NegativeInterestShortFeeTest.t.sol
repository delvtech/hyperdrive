// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { MockHyperdrive, IMockHyperdrive } from "../../../contracts/test/MockHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract NegativeInterestShortFeeTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function test_negative_interest_short_immediate_open_close_fees_fuzz(
        uint256 initialVaultSharePrice,
        int256 variableInterest
    ) external {
        // Fuzz inputs
        // initialVaultSharePrice [0.5,10]
        // variableInterest [-50,0]
        initialVaultSharePrice = initialVaultSharePrice.normalizeToRange(
            0.5e18,
            10e18
        );
        variableInterest = -variableInterest.normalizeToRange(0, 0.5e18);
        uint256 curveFee = 0.1e18;
        uint256 flatFee = 0;
        uint256 governanceFee = 1e18;
        test_negative_interest_short_immediate_open_close_fees(
            initialVaultSharePrice,
            variableInterest,
            curveFee,
            flatFee,
            governanceFee
        );
    }

    function test_negative_interest_short_immediate_open_close_fees() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - negative interest causes the share price to go down
        // - a short is opened and immediately closed
        // - set the curve fee and governance fee to 100% to make the test easier to verify
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_immediate_open_close_fees(
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
        // - a short is opened and immediately closed
        // - set the curve fee and governance fee to 100% to make the test easier to verify
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_immediate_open_close_fees(
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
        // - a short is opened and immediately closed
        // - set the curve fee and governance fee to 100% to make the test easier to verify
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_immediate_open_close_fees(
                initialVaultSharePrice,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }
    }

    function test_negative_interest_short_immediate_open_close_fees(
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
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        uint256 vaultSharePrice = poolInfo.vaultSharePrice;

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
        uint256 curveFee_ = curveFee; // avoid stack too deep error
        uint256 flatFee_ = flatFee; // avoid stack too deep error
        uint256 governanceFee_ = governanceFee; // avoid stack too deep error
        uint256 expectedGovernanceFees = expectedOpenShortFees(
            shortAmount,
            HyperdriveUtils.calculateTimeRemaining(hyperdrive, maturityTime),
            calculatedSpotPrice,
            vaultSharePrice,
            curveFee_,
            flatFee_,
            governanceFee_
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
            vaultSharePrice,
            vaultSharePrice,
            curveFee_,
            flatFee_,
            governanceFee_
        );
        assertApproxEqAbs(
            governanceFeesAfterCloseShort,
            expectedGovernanceFees,
            1
        );
    }

    function test_negative_interest_short_full_term_fees_fuzz(
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
        uint256 flatFee = 0.1e18;
        uint256 governanceFee = 1e18;
        test_negative_interest_short_full_term_fees(
            initialVaultSharePrice,
            preTradeVariableInterest,
            variableInterest,
            curveFee,
            flatFee,
            governanceFee
        );
    }

    function test_negative_interest_short_full_term_fees() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - negative interest causes the share price to go down
        // - a short is opened
        // - negative interest accrues over the full term
        // - short is closed
        // - set the flat fee to 10% and governance fee to 100% to make the test easier to verify
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_full_term_fees(
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
        // - a short is opened
        // - negative interest accrues over the full term
        // - short is closed
        // - set the flat fee to 10% and governance fee to 100% to make the test easier to verify
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_full_term_fees(
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
        // - a short is opened
        // - negative interest accrues over the full term
        // - short is closed
        // - set the flat fee to 10% and governance fee to 100% to make the test easier to verify
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_full_term_fees(
                initialVaultSharePrice,
                preTradeVariableInterest,
                variableInterest,
                curveFee,
                flatFee,
                governanceFee
            );
        }
    }

    function test_negative_interest_short_full_term_fees(
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
        uint256 openVaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;

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
        (uint256 maturityTime, ) = openShort(
            bob,
            shortAmount,
            DepositOverrides({
                asBase: true,
                destination: bob,
                // NOTE: Roughly double deposit amount needed to cover 100% flat fee
                depositAmount: shortAmount * 2,
                minSharePrice: 0,
                minSlippage: 0,
                maxSlippage: type(uint256).max,
                extraData: new bytes(0)
            })
        );

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

        // Record the closeVaultSharePrice after interest accrual.
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        uint256 closeVaultSharePrice = poolInfo.vaultSharePrice;

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
                closeVaultSharePrice,
                openVaultSharePrice,
                0,
                .1e18,
                1e18
            );
            assertApproxEqAbs(governanceFeesAfterCloseShort, expectedFees, 1);
        }
    }

    function test_negative_interest_short_half_term_fees_fuzz(
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
        uint256 flatFee = 0.1e18;
        uint256 governanceFee = 1e18;
        test_negative_interest_short_half_term_fees(
            initialVaultSharePrice,
            preTradeVariableInterest,
            variableInterest,
            curveFee,
            flatFee,
            governanceFee
        );
    }

    function test_negative_interest_short_half_term_fees() external {
        // This tests the following scenario:
        // - initial_vault_share_price > 1
        // - negative interest causes the share price to go down
        // - a short is opened
        // - negative interest accrues over the half the term
        // - short is closed
        // - set the flat fee to 10%, curve fee to 10% and governance fee to 100% to make the test easier to verify
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1.5e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_half_term_fees(
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
        // - a short is opened
        // - negative interest accrues over the half the term
        // - short is closed
        // - set the flat fee to 10%, curve fee to 10% and governance fee to 100% to make the test easier to verify
        snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 1e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_half_term_fees(
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
        // - a short is opened
        // - negative interest accrues over the half the term
        // - short is closed
        // - set the flat fee to 10%, curve fee to 10% and governance fee to 100% to make the test easier to verify
        snapshotId = vm.snapshot();
        {
            uint256 initialVaultSharePrice = 0.95e18;
            int256 preTradeVariableInterest = -0.05e18;
            int256 variableInterest = -0.1e18;
            uint256 curveFee = 0.1e18;
            uint256 flatFee = 0.1e18;
            uint256 governanceFee = 1e18;
            test_negative_interest_short_half_term_fees(
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

    function test_negative_interest_short_half_term_fees(
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
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        uint256 openVaultSharePrice = poolInfo.vaultSharePrice;
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
        (uint256 maturityTime, ) = openShort(
            bob,
            shortAmount,
            DepositOverrides({
                asBase: true,
                destination: bob,
                // NOTE: Roughly double deposit amount needed to cover 100% flat fee
                depositAmount: shortAmount * 2,
                minSharePrice: 0,
                minSlippage: 0,
                maxSlippage: type(uint256).max,
                extraData: new bytes(0)
            })
        );

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
                openVaultSharePrice,
                .1e18,
                .1e18,
                1e18
            );
            assertEq(governanceFeesAfterOpenShort, expectedGovernanceFees);
        }

        // 1/2 term matures and accrues interest
        advanceTime(POSITION_DURATION / 2, variableInterest);

        // Record the closeVaultSharePrice after interest accrual.
        poolInfo = hyperdrive.getPoolInfo();
        uint256 closeVaultSharePrice = poolInfo.vaultSharePrice;

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
                closeVaultSharePrice,
                openVaultSharePrice,
                .1e18,
                .1e18,
                1e18
            );
            assertApproxEqAbs(governanceFeesAfterCloseShort, expectedFees, 1);
        }
    }

    function expectedOpenShortFees(
        uint256 bondAmount,
        uint256 normalizedTimeRemaining,
        uint256 calculatedSpotPrice,
        uint256 vaultSharePrice,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceFee
    ) internal pure returns (uint256) {
        uint256 totalCurveFee = (ONE - calculatedSpotPrice)
            .mulUp(curveFee)
            .mulUp(bondAmount)
            .mulDivUp(normalizedTimeRemaining, vaultSharePrice);
        uint256 totalGovernanceFee = totalCurveFee.mulDown(governanceFee);
        uint256 flat = bondAmount.mulDivUp(
            ONE - normalizedTimeRemaining,
            vaultSharePrice
        );
        uint256 totalFlatFee = flat.mulUp(flatFee);
        totalGovernanceFee += totalFlatFee.mulDown(governanceFee);
        return totalGovernanceFee;
    }

    function expectedCloseShortFees(
        uint256 bondAmount,
        uint256 normalizedTimeRemaining,
        uint256 calculatedSpotPrice,
        uint256 vaultSharePrice,
        uint256 openVaultSharePrice,
        uint256 curveFee,
        uint256 flatFee,
        uint256 governanceFee
    ) internal pure returns (uint256) {
        uint256 totalCurveFee = ONE - calculatedSpotPrice;
        totalCurveFee = totalCurveFee
            .mulUp(curveFee)
            .mulUp(bondAmount)
            .mulDivUp(normalizedTimeRemaining, vaultSharePrice);
        uint256 totalGovernanceFee = totalCurveFee.mulDown(governanceFee);
        uint256 flat = bondAmount.mulDivUp(
            ONE - normalizedTimeRemaining,
            vaultSharePrice
        );
        uint256 totalFlatFee = flat.mulUp(flatFee);
        totalGovernanceFee += totalFlatFee.mulDown(governanceFee);
        return
            totalGovernanceFee.mulDivDown(vaultSharePrice, openVaultSharePrice);
    }
}
