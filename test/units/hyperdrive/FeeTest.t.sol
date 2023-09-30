// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdError } from "forge-std/StdError.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { MockHyperdrive, IMockHyperdrive } from "../../mocks/MockHyperdrive.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract FeeTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function test_governanceFeeAccrual() public {
        // Deploy and initialize a new pool with fees.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, fixedRate, 0.1e18, 0.1e18, 0.5e18);
        initialize(alice, fixedRate, contribution);

        // Open a long, record the accrued fees x share price
        uint256 baseAmount = 10e18;
        openLong(bob, baseAmount);
        uint256 governanceFeesAfterOpenLong = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued().mulDown(
                hyperdrive.getPoolInfo().sharePrice
            );

        // Time passes and the pool accrues interest at the current fixed rate.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), int256(fixedRate));

        // Collect fees and test that the fees received in the governance address have earned interest.
        vm.stopPrank();
        vm.prank(feeCollector);
        MockHyperdrive(address(hyperdrive)).collectGovernanceFee(true);
        uint256 governanceBalanceAfter = baseToken.balanceOf(feeCollector);
        assertGt(governanceBalanceAfter, governanceFeesAfterOpenLong);
    }

    // This test demonstrates that the governance fees from flat fee are NOT included in the shareReserves.
    function test_flat_gov_fee_close_long() public {
        uint256 initialSharePrice = 1e18;
        int256 variableInterest = 0.0e18;
        uint256 curveFee = 0e18;
        uint256 flatFee = .1e18;
        uint256 governanceFee = 1e18;
        uint256 timeElapsed = 73 days;

        uint256 governanceFees = 0;
        uint256 shareReservesNoFees = 0;
        uint256 bondsPurchased = 0;
        // Initialize the market with 10% flat fee and 100% governance fee
        {
            uint256 fixedRate = 0.01e18;
            deploy(
                alice,
                fixedRate,
                initialSharePrice,
                curveFee,
                flatFee,
                governanceFee
            );
            uint256 contribution = 500_000_000e18;
            initialize(alice, fixedRate, contribution);

            // Open a long position.
            uint256 basePaid = 100_000e18;
            (uint256 maturityTime, uint256 bondAmount) = openLong(
                bob,
                basePaid,
                DepositOverrides({
                    asUnderlying: true,
                    depositAmount: basePaid,
                    minSharePrice: 0,
                    minSlippage: 0,
                    maxSlippage: type(uint256).max
                })
            );
            bondsPurchased = bondAmount;
            // Get the fees accrued from opening the long.
            uint256 governanceFeesAfterOpenLong = IMockHyperdrive(
                address(hyperdrive)
            ).getGovernanceFeesAccrued();

            // 1/2 term matures and accrues interest
            advanceTime(timeElapsed, variableInterest);

            // Close the long.
            closeLong(bob, maturityTime, bondAmount);

            // Get the fees after closing the long.
            governanceFees =
                IMockHyperdrive(address(hyperdrive))
                    .getGovernanceFeesAccrued() -
                governanceFeesAfterOpenLong;
            shareReservesNoFees = hyperdrive.getPoolInfo().shareReserves;
        }

        // Initialize the market with 10% flat fee and 0% governance fee
        uint256 shareReservesFlatFee = 0;
        {
            uint256 fixedRate = 0.01e18;
            deploy(alice, fixedRate, initialSharePrice, curveFee, flatFee, 0);
            uint256 contribution = 500_000_000e18;
            initialize(alice, fixedRate, contribution);

            // Open a long position.
            uint256 basePaid = 100_000e18;
            (uint256 maturityTime, uint256 bondAmount) = openLong(
                bob,
                basePaid,
                DepositOverrides({
                    asUnderlying: true,
                    depositAmount: basePaid,
                    minSharePrice: 0,
                    minSlippage: 0,
                    maxSlippage: type(uint256).max
                })
            );

            // 1/2 term matures and accrues interest
            advanceTime(timeElapsed, variableInterest);

            // Close the long.
            closeLong(bob, maturityTime, bondAmount);
            shareReservesFlatFee = hyperdrive.getPoolInfo().shareReserves;
        }
        uint256 normalizedTimeRemaining = (timeElapsed).divDown(
            POSITION_DURATION
        );
        uint256 expectedFeeSubtractedFromShareReserves = bondsPurchased
            .mulDown(flatFee)
            .mulDown(normalizedTimeRemaining);

        // (Share Reserves Without Any Fees bc They All Went to Governance) + (10% Flat X 100% Governance Fees) - (Share Reserves With Flat Fee) = 0
        assertEq(
            shareReservesNoFees + governanceFees - shareReservesFlatFee,
            0
        );
        assertEq(shareReservesFlatFee - shareReservesNoFees, governanceFees);
        assertEq(governanceFees, expectedFeeSubtractedFromShareReserves);
    }

    // This test demonstrates that the governance fees from curve fee are NOT included in the shareReserves.
    function test_curve_gov_fee_close_long() public {
        uint256 initialSharePrice = 1e18;
        uint256 curveFee = 0.1e18;
        uint256 flatFee = 0e18;
        uint256 governanceFee = 1e18;
        uint256 timeElapsed = 73 days;

        uint256 governanceFeesFromCloseLong = 0;
        uint256 governanceFeesFromOpenLong = 0;
        uint256 shareReservesNoFees = 0;
        uint256 bondsPurchased = 0;
        uint256 spotPrice = 0;
        // Initialize the market with 10% curve fee and 100% governance fee
        {
            uint256 fixedRate = 0.01e18;
            deploy(
                alice,
                fixedRate,
                initialSharePrice,
                curveFee,
                flatFee,
                governanceFee
            );
            uint256 contribution = 500_000_000e18;
            initialize(alice, fixedRate, contribution);

            // Open a long position.
            uint256 basePaid = .01e18;
            (uint256 maturityTime, uint256 bondAmount) = openLong(
                bob,
                basePaid,
                DepositOverrides({
                    asUnderlying: true,
                    depositAmount: basePaid,
                    minSharePrice: 0,
                    minSlippage: 0,
                    maxSlippage: type(uint256).max
                })
            );
            bondsPurchased = bondAmount;
            // Get the fees accrued from opening the long.
            governanceFeesFromOpenLong = IMockHyperdrive(address(hyperdrive))
                .getGovernanceFeesAccrued();

            // 1/2 term matures and no interest accrues
            advanceTime(timeElapsed, 0);

            spotPrice = HyperdriveUtils.calculateSpotPrice(hyperdrive);

            // Close the long.
            closeLong(bob, maturityTime, bondAmount);

            // Get the fees after closing the long.
            governanceFeesFromCloseLong =
                IMockHyperdrive(address(hyperdrive))
                    .getGovernanceFeesAccrued() -
                governanceFeesFromOpenLong;
            shareReservesNoFees = hyperdrive.getPoolInfo().shareReserves;
        }

        // Test that expected Fees ~ actual Fees
        {
            uint256 normalizedTimeRemaining = FixedPointMath.ONE_18 -
                (timeElapsed).divDown(POSITION_DURATION);

            // Calculate curve fee
            uint256 expectedFeeSubtractedFromShareReserves = FixedPointMath
                .ONE_18 - spotPrice;
            expectedFeeSubtractedFromShareReserves = expectedFeeSubtractedFromShareReserves
                .mulDown(curveFee)
                .mulDown(bondsPurchased)
                .mulDown(normalizedTimeRemaining);

            // actual curve fee from close long should equal the expected curve fee from close long
            assertEq(
                governanceFeesFromCloseLong,
                expectedFeeSubtractedFromShareReserves
            );
        }

        // Initialize the market with 10% curve fee and 0% governance fee
        uint256 shareReservesCurveFee = 0;
        {
            uint256 fixedRate = 0.01e18;
            deploy(alice, fixedRate, initialSharePrice, curveFee, flatFee, 0);
            uint256 contribution = 500_000_000e18;
            initialize(alice, fixedRate, contribution);

            // Open a long position.
            uint256 basePaid = .01e18;
            (uint256 maturityTime, uint256 bondAmount) = openLong(
                bob,
                basePaid,
                DepositOverrides({
                    asUnderlying: true,
                    depositAmount: basePaid,
                    minSharePrice: 0,
                    minSlippage: 0,
                    maxSlippage: type(uint256).max
                })
            );

            // 1/2 term matures and no interest accrues
            advanceTime(timeElapsed, 0);

            // Close the long.
            closeLong(bob, maturityTime, bondAmount);
            shareReservesCurveFee = hyperdrive.getPoolInfo().shareReserves;
        }

        // The share reserves with curve fee should be greater than the share reserves without any fees + the fees from open long
        assertGt(
            shareReservesCurveFee,
            shareReservesNoFees + governanceFeesFromOpenLong
        );

        // The share reserves with curve fee should be greater than the share reserves without any fees + the fees from close long
        assertGt(
            shareReservesCurveFee,
            shareReservesNoFees + governanceFeesFromCloseLong
        );

        // (Share Reserves Without Any Fees bc They All Went to Governance) + (10% Curve X 100% Governance Fees) - (Share Reserves With Curve Fee) ~ 0
        assertApproxEqAbs(
            int256(
                shareReservesNoFees +
                    governanceFeesFromOpenLong +
                    governanceFeesFromCloseLong
            ) - int256(shareReservesCurveFee),
            0,
            1e7
        );

        // The difference between the share reserves should be equal to the actual fees
        assertApproxEqAbs(
            shareReservesCurveFee - shareReservesNoFees,
            governanceFeesFromOpenLong + governanceFeesFromCloseLong,
            1e7
        );
    }

    function test_collectFees_long() public {
        // Deploy and initialize a new pool with fees.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, fixedRate, 0.1e18, 0.1e18, 0.5e18);
        initialize(alice, fixedRate, contribution);

        // Ensure that the governance initially has zero balance
        uint256 governanceBalanceBefore = baseToken.balanceOf(feeCollector);
        assertEq(governanceBalanceBefore, 0);

        // Ensure that fees are initially zero.
        uint256 governanceFeesBeforeOpenLong = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertEq(governanceFeesBeforeOpenLong, 0);

        // Open a long.
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, baseAmount);

        // Ensure that governance fees have been accrued.
        uint256 governanceFeesAfterOpenLong = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertGt(governanceFeesAfterOpenLong, governanceFeesBeforeOpenLong);

        // Most of the term passes. The pool accrues interest at the current
        // fixed rate.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), int256(fixedRate));

        // Bob closes his long close to maturity.
        closeLong(bob, maturityTime, bondAmount);

        // Ensure that governance fees after close are greater than before close.
        uint256 governanceFeesAfterCloseLong = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertGt(governanceFeesAfterCloseLong, governanceFeesAfterOpenLong);

        // Collect fees to governance address
        vm.stopPrank();
        vm.prank(feeCollector);
        MockHyperdrive(address(hyperdrive)).collectGovernanceFee(true);

        // Ensure that governance fees after collection are zero.
        uint256 governanceFeesAfterCollection = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertEq(governanceFeesAfterCollection, 0);

        // Ensure that the governance address has received the fees.
        uint256 governanceBalanceAfter = baseToken.balanceOf(feeCollector);
        assertGt(governanceBalanceAfter, governanceBalanceBefore);
    }

    function test_collectFees_short() public {
        // Deploy and initialize a new pool with fees.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, fixedRate, 0.1e18, 0.1e18, 0.5e18);
        initialize(alice, fixedRate, contribution);

        // Ensure that the governance initially has zero balance
        uint256 governanceBalanceBefore = baseToken.balanceOf(governance);
        assertEq(governanceBalanceBefore, 0);

        // Ensure that fees are initially zero.
        uint256 governanceFeesBeforeOpenShort = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertEq(governanceFeesBeforeOpenShort, 0);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // Ensure that governance fees have been accrued.
        uint256 governanceFeesAfterOpenShort = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertGt(governanceFeesAfterOpenShort, governanceFeesBeforeOpenShort);

        // Most of the term passes. The pool accrues interest at the current
        // fixed rate.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), int256(fixedRate));

        // Redeem the bonds.
        closeShort(bob, maturityTime, bondAmount);

        // Ensure that governance fees after close are greater than before close.
        uint256 governanceFeesAfterCloseShort = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertGt(governanceFeesAfterCloseShort, governanceFeesAfterOpenShort);

        // collect governance fees
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        MockHyperdrive(address(hyperdrive)).collectGovernanceFee(true);
        vm.stopPrank();
        vm.prank(governance);
        MockHyperdrive(address(hyperdrive)).collectGovernanceFee(true);

        // Ensure that governance fees after collection are zero.
        uint256 governanceFeesAfterCollection = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertEq(governanceFeesAfterCollection, 0);

        // Ensure that the governance address has received the fees.
        uint256 governanceBalanceAfter = baseToken.balanceOf(feeCollector);
        assertGt(governanceBalanceAfter, governanceBalanceBefore);
    }

    function test_calculateOpenLongFees() public {
        // Deploy and initialize a new pool with fees.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, fixedRate, 0.1e18, 0.1e18, 0.5e18);
        initialize(alice, fixedRate, contribution);

        (uint256 curveFee, uint256 governanceCurveFee) = MockHyperdrive(
            address(hyperdrive)
        ).calculateFeesOutGivenSharesIn(
                1e18, // amountIn
                0.5e18, // spotPrice
                1e18 //sharePrice
            );
        // total curve fee = ((1 / p) - 1) * phi_curve * c * dz
        // ((1/0.5)-1) * 0.1*1*1 = 0.1
        assertEq(curveFee, 0.1e18);
        // governance curve fee = total curve fee * phi_gov
        // 0.1 * 0.5 = 0.05
        assertEq(governanceCurveFee, 0.05e18);
    }

    function test_calcFeesOutGivenBondsIn() public {
        // Deploy and initialize a new pool with fees.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, fixedRate, 0.1e18, 0.1e18, 0.5e18);
        initialize(alice, fixedRate, contribution);
        (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 totalGovernanceFee
        ) = MockHyperdrive(address(hyperdrive)).calculateFeesOutGivenBondsIn(
                1e18, // amountIn
                1e18, // timeRemaining
                0.9e18, // spotPrice
                1e18 // sharePrice
            );
        // curve fee = ((1 - p) * phi_curve * d_y * t) / c
        // ((1-0.9)*0.1*1*1)/1 = 0.01
        assertEq(totalCurveFee + totalFlatFee, 0.01e18);

        assertEq(totalGovernanceFee, 0.005e18);

        (totalCurveFee, totalFlatFee, totalGovernanceFee) = MockHyperdrive(
            address(hyperdrive)
        ).calculateFeesOutGivenBondsIn(
                1e18, // amountIn
                0, // timeRemaining
                0.9e18, // spotPrice
                1e18 // sharePrice
            );
        assertEq(totalCurveFee + totalFlatFee, 0.1e18);
        assertEq(totalGovernanceFee, 0.05e18);
    }

    function test_calcFeesInGivenBondsOut() public {
        // Deploy and initialize a new pool with fees.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, fixedRate, 0.1e18, 0.1e18, 0.5e18);
        initialize(alice, fixedRate, contribution);
        (
            uint256 curveFee,
            uint256 flatFee,
            uint256 governanceCurveFee,
            uint256 governanceFlatFee
        ) = MockHyperdrive(address(hyperdrive)).calculateFeesInGivenBondsOut(
                1e18, // amountOut
                1e18, // timeRemaining
                0.9e18, // spotPrice
                1e18 // sharePrice
            );
        assertEq(curveFee, 0.01e18);
        assertEq(flatFee, 0e18);
        assertEq(governanceCurveFee, 0.005e18);
        assertEq(governanceFlatFee, 0e18);

        (
            curveFee,
            flatFee,
            governanceCurveFee,
            governanceFlatFee
        ) = MockHyperdrive(address(hyperdrive)).calculateFeesInGivenBondsOut(
            1e18, // amountOut
            0, // timeRemaining
            0.9e18, // spotPrice
            1e18 // sharePrice
        );
        assertEq(curveFee, 0e18);
        assertEq(flatFee, 0.1e18);
        assertEq(governanceCurveFee, 0e18);
        assertEq(governanceFlatFee, 0.05e18);
    }
}
