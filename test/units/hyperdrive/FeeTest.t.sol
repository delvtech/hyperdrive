// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { MockHyperdrive } from "contracts/test/MockHyperdrive.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";

contract FeeTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_governanceFeeAccrual() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;

        // Deploy and initialize a new pool with fees.
        deploy(alice, apr, 0.1e18, 0.1e18, 0.5e18, governance);
        initialize(alice, apr, contribution);

        // Open a long, record the accrued fees x share price
        uint256 baseAmount = 10e18;
        openLong(bob, baseAmount);
        uint256 governanceFeesAfterOpenLong = MockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued().mulDown(
                HyperdriveUtils.getPoolInfo(hyperdrive).sharePrice
            );

        // Time passes and the pool accrues interest at the current apr.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), int256(apr));

        // Collect fees and test that the fees received in the governance address have earned interest.
        MockHyperdrive(address(hyperdrive)).collectGovernanceFee();
        uint256 governanceBalanceAfter = baseToken.balanceOf(governance);
        assertGt(governanceBalanceAfter, governanceFeesAfterOpenLong);
    }

    function test_collectFees_long() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;

        // Deploy and initialize a new pool with fees.
        deploy(alice, apr, 0.1e18, 0.1e18, 0.5e18, governance);
        initialize(alice, apr, contribution);

        // Ensure that the governance initially has zero balance
        uint256 governanceBalanceBefore = baseToken.balanceOf(governance);
        assertEq(governanceBalanceBefore, 0);

        // Ensure that fees are initially zero.
        uint256 governanceFeesBeforeOpenLong = MockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertEq(governanceFeesBeforeOpenLong, 0);

        // Open a long.
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, baseAmount);

        // Ensure that gov fees have been accrued.
        uint256 governanceFeesAfterOpenLong = MockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertGt(governanceFeesAfterOpenLong, governanceFeesBeforeOpenLong);

        // Most of the term passes. The pool accrues interest at the current apr.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), int256(apr));

        // Bob closes his long close to maturity.
        closeLong(bob, maturityTime, bondAmount);

        // Ensure that governance fees after close are greater than before close.
        uint256 governanceFeesAfterCloseLong = MockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertGt(governanceFeesAfterCloseLong, governanceFeesAfterOpenLong);

        // Collect fees to governance address
        MockHyperdrive(address(hyperdrive)).collectGovernanceFee();

        // Ensure that governance fees after collection are zero.
        uint256 governanceFeesAfterCollection = MockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertEq(governanceFeesAfterCollection, 0);

        // Ensure that the governance address has received the fees.
        uint256 governanceBalanceAfter = baseToken.balanceOf(governance);
        assertGt(governanceBalanceAfter, governanceBalanceBefore);
    }

    function test_collectFees_short() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;

        // Deploy and initialize a new pool with fees.
        deploy(alice, apr, 0.1e18, 0.1e18, 0.5e18, governance);
        initialize(alice, apr, contribution);

        // Ensure that the governance initially has zero balance
        uint256 governanceBalanceBefore = baseToken.balanceOf(governance);
        assertEq(governanceBalanceBefore, 0);

        // Ensure that fees are initially zero.
        uint256 governanceFeesBeforeOpenShort = MockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertEq(governanceFeesBeforeOpenShort, 0);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // Ensure that governance fees have been accrued.
        uint256 governanceFeesAfterOpenShort = MockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertGt(governanceFeesAfterOpenShort, governanceFeesBeforeOpenShort);

        // Most of the term passes. The pool accrues interest at the current apr.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), int256(apr));

        // Redeem the bonds.
        closeShort(bob, maturityTime, bondAmount);

        // Ensure that governance fees after close are greater than before close.
        uint256 governanceFeesAfterCloseShort = MockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertGt(governanceFeesAfterCloseShort, governanceFeesAfterOpenShort);

        // collect governance fees
        MockHyperdrive(address(hyperdrive)).collectGovernanceFee();

        // Ensure that governance fees after collection are zero.
        uint256 governanceFeesAfterCollection = MockHyperdrive(
            address(hyperdrive)
        ).getGovernanceFeesAccrued();
        assertEq(governanceFeesAfterCollection, 0);

        // Ensure that the governance address has received the fees.
        uint256 governanceBalanceAfter = baseToken.balanceOf(governance);
        assertGt(governanceBalanceAfter, governanceBalanceBefore);
    }

    function test_calcFeesOutGivenSharesIn() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        // Deploy and initialize a new pool with fees.
        deploy(alice, apr, 0.1e18, 0.1e18, 0.5e18, governance);
        initialize(alice, apr, contribution);

        (
            uint256 curveFee,
            uint256 flatFee,
            uint256 governanceCurveFee,
            uint256 governanceFlatFee
        ) = MockHyperdrive(address(hyperdrive)).calculateFeesOutGivenSharesIn(
                1 ether, // amountIn
                1 ether, //amountOut
                1 ether, // timeRemaining
                0.5 ether, // spotPrice
                1 ether // sharePrice
            );
        // curve fee = ((1 / p) - 1) * phi_curve * c * d_z * t
        // ((1/.5)-1) * .1*1*1*1 = .1
        assertEq(curveFee, .1 ether);
        assertEq(governanceCurveFee, .05 ether);

        assertEq(flatFee, 0 ether);
        assertEq(governanceFlatFee, 0 ether);

        (
            curveFee,
            flatFee,
            governanceCurveFee,
            governanceFlatFee
        ) = MockHyperdrive(address(hyperdrive)).calculateFeesOutGivenSharesIn(
            1 ether, // amountIn
            1 ether, // amountOut
            0, // timeRemaining
            0.5 ether, // spotPrice
            1 ether // sharePrice
        );
        assertEq(curveFee, 0 ether);

        assertEq(governanceCurveFee, 0 ether);
        assertEq(flatFee, 0.1 ether);
        assertEq(governanceFlatFee, 0.05 ether);
    }

    // TODO Maybe move into HyperdriveMath.t.sol?
    function test_calculateFeesOutGivenBondsIn() public {
        (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 totalGovernanceFee
        ) = HyperdriveMath.calculateFeesOutGivenBondsIn(
                1 ether, // bondIn
                1 ether, // timeRemaining
                0.9 ether, // spotPrice
                1 ether, // sharePrice
                0.1e18, // curveFee
                0.1e18, // flatFee
                0.5e18 // governanceFee
        );
        // curve fee = ((1 - p) * phi_curve * d_y * t) / c
        // ((1-.9)*.1*1*1)/1 = .01
        assertEq(totalCurveFee + totalFlatFee, .01 ether);

        assertEq(totalGovernanceFee, .005 ether);

        (totalCurveFee, totalFlatFee, totalGovernanceFee) = HyperdriveMath.calculateFeesOutGivenBondsIn(
                1 ether, // amountIn
                0, // timeRemaining
                0.9 ether, // spotPrice
                1 ether, // sharePrice
                0.1e18, // curveFee
                0.1e18, // flatFee
                0.5e18 // governanceFee
            );
        assertEq(totalCurveFee + totalFlatFee, 0.1 ether);
        assertEq(totalGovernanceFee, 0.05 ether);
    }

    function test_calcFeesInGivenBondsOut() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        // Deploy and initialize a new pool with fees.
        deploy(alice, apr, 0.1e18, 0.1e18, 0.5e18, governance);
        initialize(alice, apr, contribution);
        (
            uint256 curveFee,
            uint256 flatFee,
            uint256 governanceCurveFee,
            uint256 governanceFlatFee
        ) = MockHyperdrive(address(hyperdrive)).calculateFeesInGivenBondsOut(
                1 ether, // amountOut
                1 ether, // timeRemaining
                0.9 ether, // spotPrice
                1 ether // sharePrice
            );
        assertEq(curveFee, .01 ether);
        assertEq(flatFee, 0 ether);
        assertEq(governanceCurveFee, .005 ether);
        assertEq(governanceFlatFee, 0 ether);

        (
            curveFee,
            flatFee,
            governanceCurveFee,
            governanceFlatFee
        ) = MockHyperdrive(address(hyperdrive)).calculateFeesInGivenBondsOut(
            1 ether, // amountOut
            0, // timeRemaining
            0.9 ether, // spotPrice
            1 ether // sharePrice
        );
        assertEq(curveFee, 0 ether);
        assertEq(flatFee, 0.1 ether);
        assertEq(governanceCurveFee, 0 ether);
        assertEq(governanceFlatFee, 0.05 ether);
    }
}
