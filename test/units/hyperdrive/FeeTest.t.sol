// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { MockHyperdrive, IMockHyperdrive } from "../../../contracts/test/MockHyperdrive.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract FeeTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    uint256 internal deployCurveFee = 0.1e18; // 10%
    uint256 internal deployFlatFee = 0.01e18; // 0.1%
    uint256 internal deployGovernanceLPFee = 0.5e18; // 50%
    uint256 internal deployGovernanceZombieFee = 0.5e18; // 50%

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_governanceFeeAccrual_invalidFeeDestination_failure() public {
        // Deploy and initialize a new pool with fees.
        uint256 apr = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(
            alice,
            apr,
            deployCurveFee,
            deployFlatFee,
            deployGovernanceLPFee,
            deployGovernanceZombieFee
        );
        initialize(alice, apr, contribution);

        // Open a long and ensure that the governance fees accrued are non-zero.
        uint256 baseAmount = 10e18;
        openLong(bob, baseAmount);
        assertGt(hyperdrive.getUncollectedGovernanceFees(), 0);

        // Attempt to collect fees with an invalid destination.
        vm.stopPrank();
        vm.prank(feeCollector);
        vm.expectRevert(IHyperdrive.InvalidFeeDestination.selector);
        hyperdrive.collectGovernanceFee(
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_governanceFeeAccrual() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;

        // Deploy and initialize a new pool with fees.
        deploy(
            alice,
            apr,
            deployCurveFee,
            deployFlatFee,
            deployGovernanceLPFee,
            deployGovernanceZombieFee
        );
        initialize(alice, apr, contribution);

        // Open a long, record the accrued fees x share price
        uint256 baseAmount = 10e18;
        openLong(bob, baseAmount);
        uint256 governanceFeesAfterOpenLong = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued().mulDown(
                hyperdrive.getPoolInfo().vaultSharePrice
            );

        // Time passes and the pool accrues interest at the current apr.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), int256(apr));

        // Collect fees and test that the fees received in the governance address
        // have earned interest.
        vm.stopPrank();
        vm.prank(feeCollector);
        hyperdrive.collectGovernanceFee(
            IHyperdrive.Options({
                destination: feeCollector,
                asBase: true,
                extraData: new bytes(0)
            })
        );
        uint256 governanceBalanceAfter = baseToken.balanceOf(feeCollector);
        assertGt(governanceBalanceAfter, governanceFeesAfterOpenLong);

        // Ensure that the correct event was emitted.
        verifyCollectGovernanceFeeEvent(feeCollector, governanceBalanceAfter);
    }

    function test_zombie_interest_governance_fee() external {
        uint256 initialVaultSharePrice = 1e18;

        // Initialize the market
        uint256 apr = 0.05e18;
        // Set zombie fee to 100% to verify it works.
        uint256 governanceZombieFee = 1e18;
        deploy(
            alice,
            apr,
            initialVaultSharePrice,
            0,
            0,
            0,
            governanceZombieFee
        );
        uint256 contribution = 100e18;
        initialize(alice, apr, contribution);

        // Open a long.
        uint256 basePaidLong = 10e18;
        (uint256 maturityTimeLong, uint256 bondAmountLong) = openLong(
            alice,
            basePaidLong
        );

        // Wait two term lengths.
        advanceTimeWithCheckpoints(POSITION_DURATION * 2, int256(apr));

        // Close the long 1 term too late.
        closeLong(alice, maturityTimeLong, bondAmountLong);

        // Verify that the value represented in the share reserves is <= the actual amount in the contract.
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        uint256 governanceFeesAccrued = IMockHyperdrive(address(hyperdrive))
            .getGovernanceFeesAccrued();
        uint256 baseReserves = hyperdrive.getPoolInfo().shareReserves.mulDown(
            vaultSharePrice
        );
        uint256 zombieShareReserves = hyperdrive
            .getPoolInfo()
            .zombieShareReserves;
        uint256 expectedBalance = baseReserves +
            governanceFeesAccrued.mulDown(vaultSharePrice) +
            zombieShareReserves.mulDown(vaultSharePrice);
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            expectedBalance,
            500 wei
        );

        // Verify that the governance fees accrued as expected.
        (, int256 expectedGovernanceFeesAccrued) = HyperdriveUtils
            .calculateCompoundInterest(
                bondAmountLong,
                int256(apr),
                POSITION_DURATION
            );
        assertApproxEqAbs(
            governanceFeesAccrued.mulDown(vaultSharePrice),
            uint256(expectedGovernanceFeesAccrued),
            1e4
        );

        // Governance zombie fees should be greater than 0.
        assertGt(governanceFeesAccrued, 0);
    }

    // This test demonstrates that the governance fees from flat fee are NOT included in the shareReserves.
    function test_flat_gov_fee_close_long() public {
        uint256 initialVaultSharePrice = 1e18;
        int256 variableInterest = 0.0e18;
        uint256 curveFee = 0e18; // 0%
        uint256 flatFee = 0.001e18; // 0.1%
        uint256 governanceLPFee = 1e18; // 100%
        uint256 governanceZombieFee = 0; // 0%
        uint256 timeElapsed = 73 days;

        uint256 governanceFees = 0;
        uint256 shareReservesNoFees = 0;
        uint256 bondsPurchased = 0;
        // Initialize the market with 10% flat fee and 100% governance fee
        {
            uint256 apr = 0.01e18;
            deploy(
                alice,
                apr,
                initialVaultSharePrice,
                curveFee,
                flatFee,
                governanceLPFee,
                governanceZombieFee
            );
            uint256 contribution = 500_000_000e18;
            initialize(alice, apr, contribution);

            // Open a long position.
            uint256 basePaid = 100_000e18;
            (uint256 maturityTime, uint256 bondAmount) = openLong(
                bob,
                basePaid,
                DepositOverrides({
                    asBase: true,
                    destination: bob,
                    depositAmount: basePaid,
                    minSharePrice: 0,
                    minSlippage: 0,
                    maxSlippage: type(uint256).max,
                    extraData: new bytes(0)
                })
            );
            bondsPurchased = bondAmount;
            // Get the fees accrued from opening the long.
            uint256 governanceFeesAfterOpenLong = IMockHyperdrive(
                address(hyperdrive)
            ).getGovernanceFeesAccrued();

            // 1/2 term matures and accrues interest
            int256 _variableInterest = variableInterest; // Stack too deep error
            advanceTime(timeElapsed, _variableInterest);

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
            uint256 apr = 0.01e18;
            deploy(alice, apr, initialVaultSharePrice, curveFee, flatFee, 0, 0);
            uint256 contribution = 500_000_000e18;
            initialize(alice, apr, contribution);

            // Open a long position.
            uint256 basePaid = 100_000e18;
            (uint256 maturityTime, uint256 bondAmount) = openLong(
                bob,
                basePaid,
                DepositOverrides({
                    asBase: true,
                    destination: bob,
                    depositAmount: basePaid,
                    minSharePrice: 0,
                    minSlippage: 0,
                    maxSlippage: type(uint256).max,
                    extraData: new bytes(0)
                })
            );

            // 1/2 term matures and accrues interest
            int256 _variableInterest = variableInterest; // Stack too deep error
            advanceTime(timeElapsed, _variableInterest);

            // Close the long.
            closeLong(bob, maturityTime, bondAmount);
            shareReservesFlatFee = hyperdrive.getPoolInfo().shareReserves;
        }
        uint256 normalizedTimeRemaining = (timeElapsed).divDown(
            POSITION_DURATION
        );
        uint256 expectedFeeSubtractedFromShareReserves = bondsPurchased
            .mulUp(flatFee)
            .mulUp(normalizedTimeRemaining);

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
        uint256 initialVaultSharePrice = 1e18;
        uint256 curveFee = 0.1e18; // 10%
        uint256 flatFee = 0; // 0%
        uint256 governanceLPFee = 1e18; // 100%
        uint256 governanceZombieFee = 0; // 0%
        uint256 timeElapsed = 73 days;

        uint256 governanceFeesFromCloseLong = 0;
        uint256 governanceFeesFromOpenLong = 0;
        uint256 effectiveShareReservesNoFees = 0;
        uint256 bondsPurchased = 0;
        uint256 spotPrice = 0;
        // Initialize the market with 10% curve fee and 100% governance fee
        {
            uint256 apr = 0.01e18;
            deploy(
                alice,
                apr,
                initialVaultSharePrice,
                curveFee,
                flatFee,
                governanceLPFee,
                governanceZombieFee
            );
            uint256 contribution = 500_000_000e18;
            initialize(alice, apr, contribution);

            // Open a long position.
            uint256 basePaid = .01e18;
            (uint256 maturityTime, uint256 bondAmount) = openLong(
                bob,
                basePaid,
                DepositOverrides({
                    asBase: true,
                    destination: bob,
                    depositAmount: basePaid,
                    minSharePrice: 0,
                    minSlippage: 0,
                    maxSlippage: type(uint256).max,
                    extraData: new bytes(0)
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
            effectiveShareReservesNoFees = HyperdriveMath
                .calculateEffectiveShareReserves(
                    hyperdrive.getPoolInfo().shareReserves,
                    hyperdrive.getPoolInfo().shareAdjustment
                );
        }

        // Test that expected Fees ~ actual Fees
        {
            uint256 normalizedTimeRemaining = ONE -
                (timeElapsed).divDown(POSITION_DURATION);

            // Calculate curve fee
            uint256 expectedFeeSubtractedFromShareReserves = ONE - spotPrice;
            uint256 _curveFee = curveFee;
            expectedFeeSubtractedFromShareReserves = expectedFeeSubtractedFromShareReserves
                .mulUp(_curveFee)
                .mulUp(bondsPurchased)
                .mulUp(normalizedTimeRemaining);

            // actual curve fee from close long should equal the expected curve fee from close long
            assertEq(
                governanceFeesFromCloseLong,
                expectedFeeSubtractedFromShareReserves
            );
        }

        // Initialize the market with 10% curve fee and 0% governance fee
        uint256 effectiveShareReservesCurveFee = 0;
        {
            uint256 apr = 0.01e18;
            deploy(alice, apr, initialVaultSharePrice, curveFee, flatFee, 0, 0);
            uint256 contribution = 500_000_000e18;
            initialize(alice, apr, contribution);

            // Open a long position.
            uint256 basePaid = .01e18;
            (uint256 maturityTime, uint256 bondAmount) = openLong(
                bob,
                basePaid,
                DepositOverrides({
                    asBase: true,
                    destination: bob,
                    depositAmount: basePaid,
                    minSharePrice: 0,
                    minSlippage: 0,
                    maxSlippage: type(uint256).max,
                    extraData: new bytes(0)
                })
            );

            // 1/2 term matures and no interest accrues
            advanceTime(timeElapsed, 0);

            // Close the long.
            closeLong(bob, maturityTime, bondAmount);
            effectiveShareReservesCurveFee = HyperdriveMath
                .calculateEffectiveShareReserves(
                    hyperdrive.getPoolInfo().shareReserves,
                    hyperdrive.getPoolInfo().shareAdjustment
                );
        }

        // The share reserves with curve fee should be greater than the share reserves without any fees + the fees from open long
        assertGt(
            effectiveShareReservesCurveFee,
            effectiveShareReservesNoFees + governanceFeesFromOpenLong
        );

        // The share reserves with curve fee should be greater than the share reserves without any fees + the fees from close long
        assertGt(
            effectiveShareReservesCurveFee,
            effectiveShareReservesNoFees + governanceFeesFromCloseLong
        );

        // (Share Reserves Without Any Fees bc They All Went to Governance) + (10% Curve X 100% Governance Fees) - (Share Reserves With Curve Fee) ~ 0
        assertApproxEqAbs(
            int256(
                effectiveShareReservesNoFees +
                    governanceFeesFromOpenLong +
                    governanceFeesFromCloseLong
            ) - int256(effectiveShareReservesCurveFee),
            0,
            1e8
        );

        // The difference between the share reserves should be equal to the actual fees
        assertApproxEqAbs(
            effectiveShareReservesCurveFee - effectiveShareReservesNoFees,
            governanceFeesFromOpenLong + governanceFeesFromCloseLong,
            1e8
        );
    }

    function test_collectFees_long() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;

        // Deploy and initialize a new pool with fees.
        deploy(
            alice,
            apr,
            deployCurveFee,
            deployFlatFee,
            deployGovernanceLPFee,
            deployGovernanceZombieFee
        );
        initialize(alice, apr, contribution);

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

        // Most of the term passes. The pool accrues interest at the current apr.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), int256(apr));

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
        hyperdrive.collectGovernanceFee(
            IHyperdrive.Options({
                destination: feeCollector,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that governance fees after collection are zero.
        uint256 governanceFeesAfterCollection = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertEq(governanceFeesAfterCollection, 0);

        // Ensure that the governance address has received the fees.
        uint256 governanceBalanceAfter = baseToken.balanceOf(feeCollector);
        assertGt(governanceBalanceAfter, governanceBalanceBefore);

        // Ensure that the correct event was emitted.
        verifyCollectGovernanceFeeEvent(
            feeCollector,
            governanceBalanceAfter - governanceBalanceBefore
        );
    }

    function test_collectFees_short() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;

        // Deploy and initialize a new pool with fees.
        deploy(
            alice,
            apr,
            deployCurveFee,
            deployFlatFee,
            deployGovernanceLPFee,
            deployGovernanceZombieFee
        );
        initialize(alice, apr, contribution);

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

        // Most of the term passes. The pool accrues interest at the current apr.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), int256(apr));

        // Redeem the bonds.
        closeShort(bob, maturityTime, bondAmount);

        // Ensure that governance fees after close are greater than before close.
        uint256 governanceFeesAfterCloseShort = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertGt(governanceFeesAfterCloseShort, governanceFeesAfterOpenShort);

        // Attempting to collect governance fees with the wrong address should
        // fail.
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        hyperdrive.collectGovernanceFee(
            IHyperdrive.Options({
                destination: feeCollector,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Collect governance fees.
        vm.stopPrank();
        vm.prank(governance);
        hyperdrive.collectGovernanceFee(
            IHyperdrive.Options({
                destination: feeCollector,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that governance fees after collection are zero.
        uint256 governanceFeesAfterCollection = IMockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertEq(governanceFeesAfterCollection, 0);

        // Ensure that the governance address has received the fees.
        uint256 governanceBalanceAfter = baseToken.balanceOf(feeCollector);
        assertGt(governanceBalanceAfter, governanceBalanceBefore);

        // Ensure that the correct event was emitted.
        verifyCollectGovernanceFeeEvent(
            feeCollector,
            governanceBalanceAfter - governanceBalanceBefore
        );
    }

    function test_calculateOpenLongFees() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        // Deploy and initialize a new pool with fees.
        deploy(
            alice,
            apr,
            deployCurveFee,
            deployFlatFee,
            deployGovernanceLPFee,
            deployGovernanceZombieFee
        );
        initialize(alice, apr, contribution);

        (uint256 curveFee, uint256 governanceCurveFee) = MockHyperdrive(
            address(hyperdrive)
        ).calculateFeesGivenShares(
                1 ether, // amountIn
                0.5 ether, // spotPrice
                1 ether //vaultSharePrice
            );
        // total curve fee = ((1 / p) - 1) * phi_curve * c * dz
        // ((1/.5)-1) * .1*1*1 = .1
        assertEq(curveFee, .1 ether);
        // governance curve fee = total curve fee * phi_gov
        // .1 * 0.5 = .05
        assertEq(governanceCurveFee, .05 ether);
    }

    function test_calcFeesOutGivenBondsIn() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        // Deploy and initialize a new pool with fees.
        deploy(
            alice,
            apr,
            deployCurveFee,
            0.1e18,
            deployGovernanceLPFee,
            deployGovernanceZombieFee
        );
        initialize(alice, apr, contribution);
        (
            uint256 curveFee,
            uint256 flatFee,
            uint256 governanceCurveFee,
            uint256 totalGovernanceFee
        ) = MockHyperdrive(address(hyperdrive)).calculateFeesGivenBonds(
                1 ether, // amount
                1 ether, // timeRemaining
                0.9 ether, // spotPrice
                1 ether // vaultSharePrice
            );
        // curve fee = ((1 - p) * phi_curve * d_y * t) / c
        // ((1-.9)*.1*1*1)/1 = .01
        assertEq(curveFee + flatFee, .01 ether);

        assertEq(totalGovernanceFee, .005 ether);

        (
            curveFee,
            flatFee,
            governanceCurveFee,
            totalGovernanceFee
        ) = MockHyperdrive(address(hyperdrive)).calculateFeesGivenBonds(
            1 ether, // amount
            0, // timeRemaining
            0.9 ether, // spotPrice
            1 ether // vaultSharePrice
        );
        assertEq(curveFee + flatFee, 0.1 ether);
        assertEq(totalGovernanceFee, 0.05 ether);
    }

    function test_calcFeesInGivenBondsOut() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        // Deploy and initialize a new pool with fees.
        deploy(
            alice,
            apr,
            deployCurveFee,
            0.1e18,
            deployGovernanceLPFee,
            deployGovernanceZombieFee
        );
        initialize(alice, apr, contribution);
        (
            uint256 curveFee,
            uint256 flatFee,
            uint256 governanceCurveFee,
            uint256 totalGovernanceFee
        ) = MockHyperdrive(address(hyperdrive)).calculateFeesGivenBonds(
                1 ether, // amount
                1 ether, // timeRemaining
                0.9 ether, // spotPrice
                1 ether // vaultSharePrice
            );
        assertEq(curveFee, .01 ether);
        assertEq(flatFee, 0 ether);
        assertEq(governanceCurveFee, .005 ether);
        assertEq(totalGovernanceFee - governanceCurveFee, 0 ether);

        (
            curveFee,
            flatFee,
            governanceCurveFee,
            totalGovernanceFee
        ) = MockHyperdrive(address(hyperdrive)).calculateFeesGivenBonds(
            1 ether, // amount
            0, // timeRemaining
            0.9 ether, // spotPrice
            1 ether // vaultSharePrice
        );
        assertEq(curveFee, 0 ether);
        assertEq(flatFee, 0.1 ether);
        assertEq(governanceCurveFee, 0 ether);
        assertEq(totalGovernanceFee - governanceCurveFee, 0.05 ether);
    }

    function verifyCollectGovernanceFeeEvent(
        address collector,
        uint256 baseAmount
    ) internal {
        // Get the recorded `CollectGovernanceFee` logs.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CollectGovernanceFee.selector
        );

        // Verify that the log was correct.
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(log.topics.length, 2); // the event name and the collector
        assertEq(address(uint160(uint256(log.topics[1]))), collector);
        (
            uint256 eventAmount,
            uint256 eventVaultSharePrice,
            bool eventAsBase
        ) = abi.decode(log.data, (uint256, uint256, bool));
        assertEq(eventAmount, baseAmount);
        assertApproxEqAbs(
            eventVaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            1
        );
        assertEq(eventAsBase, true);

        // Start recording logs again.
        vm.recordLogs();
    }
}
