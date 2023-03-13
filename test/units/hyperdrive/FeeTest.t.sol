// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { MockHyperdrive } from "contracts/test/MockHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";

contract FeeTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_govFeeAccrual() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;

        // Deploy and initialize a new pool with fees.
        deploy(alice, apr, 0.1e18, 0.1e18, 0.5e18, governance);
        initialize(alice, apr, contribution);

        // Open a long, record the accrued fees x share price
        uint256 baseAmount = 10e18;
        openLong(bob, baseAmount);
        uint256 govFeesAfterOpenLong = hyperdrive.getGovFeesAccrued().mulDown(
            hyperdrive.getSharePrice()
        );

        // Time passes and the pool accrues interest at the current apr.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), int256(apr));

        // Collect fees and test that the fees received in the governance address have earned interest.
        hyperdrive.collectGovFee();
        uint256 govBalanceAfter = baseToken.balanceOf(governance);
        assertGt(govBalanceAfter, govFeesAfterOpenLong);
    }

    function test_collectFees_long() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;

        // Deploy and initialize a new pool with fees.
        deploy(alice, apr, 0.1e18, 0.1e18, 0.5e18, governance);
        initialize(alice, apr, contribution);

        // Ensure that the governance initially has zero balance
        uint256 govBalanceBefore = baseToken.balanceOf(governance);
        assertEq(govBalanceBefore, 0);

        // Ensure that fees are initially zero.
        uint256 govFeesBeforeOpenLong = hyperdrive.getGovFeesAccrued();
        assertEq(govFeesBeforeOpenLong, 0);

        // Open a long.
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, baseAmount);

        // Ensure that gov fees have been accrued.
        uint256 govFeesAfterOpenLong = hyperdrive.getGovFeesAccrued();
        assertGt(govFeesAfterOpenLong, govFeesBeforeOpenLong);

        // Most of the term passes. The pool accrues interest at the current apr.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), int256(apr));

        // Bob closes his long close to maturity.
        closeLong(bob, maturityTime, bondAmount);

        // Ensure that gov fees after close are greater than before close.
        uint256 govFeesAfterCloseLong = hyperdrive.getGovFeesAccrued();
        assertGt(govFeesAfterCloseLong, govFeesAfterOpenLong);

        // Collect fees to governance address
        hyperdrive.collectGovFee();

        // Ensure that gov fees after collection are zero.
        uint256 govFeesAfterCollection = hyperdrive.getGovFeesAccrued();
        assertEq(govFeesAfterCollection, 0);

        // Ensure that the governance address has received the fees.
        uint256 govBalanceAfter = baseToken.balanceOf(governance);
        assertGt(govBalanceAfter, govBalanceBefore);
    }

    function test_collectFees_short() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;

        // Deploy and initialize a new pool with fees.
        deploy(alice, apr, 0.1e18, 0.1e18, 0.5e18, governance);
        initialize(alice, apr, contribution);

        // Ensure that the governance initially has zero balance
        uint256 govBalanceBefore = baseToken.balanceOf(governance);
        assertEq(govBalanceBefore, 0);

        // Ensure that fees are initially zero.
        uint256 govFeesBeforeOpenShort = hyperdrive.getGovFeesAccrued();
        assertEq(govFeesBeforeOpenShort, 0);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // Ensure that gov fees have been accrued.
        uint256 govFeesAfterOpenShort = hyperdrive.getGovFeesAccrued();
        assertGt(govFeesAfterOpenShort, govFeesBeforeOpenShort);

        // Most of the term passes. The pool accrues interest at the current apr.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), int256(apr));

        // Redeem the bonds.
        closeShort(bob, maturityTime, bondAmount);

        // Ensure that gov fees after close are greater than before close.
        uint256 govFeesAfterCloseShort = hyperdrive.getGovFeesAccrued();
        assertGt(govFeesAfterCloseShort, govFeesAfterOpenShort);

        // collect governance fees
        hyperdrive.collectGovFee();

        // Ensure that gov fees after collection are zero.
        uint256 govFeesAfterCollection = hyperdrive.getGovFeesAccrued();
        assertEq(govFeesAfterCollection, 0);

        // Ensure that the governance address has received the fees.
        uint256 govBalanceAfter = baseToken.balanceOf(governance);
        assertGt(govBalanceAfter, govBalanceBefore);
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
            uint256 govCurveFee,
            uint256 govFlatFee
        ) = hyperdrive.calculateFeesOutGivenSharesIn(
                1 ether, // amountIn
                1 ether, //amountOut
                1 ether, // timeRemaining
                0.5 ether, // spotPrice
                1 ether // sharePrice
            );
        // curve fee = ((1 / p) - 1) * phi_curve * c * d_z * t
        // ((1/.5)-1) * .1*1*1*1 = .1
        assertEq(curveFee, .1 ether);
        assertEq(govCurveFee, .05 ether);

        assertEq(flatFee, 0 ether);
        assertEq(govFlatFee, 0 ether);

        (curveFee, flatFee, govCurveFee, govFlatFee) = hyperdrive
            .calculateFeesOutGivenSharesIn(
                1 ether, // amountIn
                1 ether, // amountOut
                0, // timeRemaining
                0.5 ether, // spotPrice
                1 ether // sharePrice
            );
        assertEq(curveFee, 0 ether);

        assertEq(govCurveFee, 0 ether);
        assertEq(flatFee, 0.1 ether);
        assertEq(govFlatFee, 0.05 ether);
    }

    function test_calcFeesOutGivenBondsIn() public {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        // Deploy and initialize a new pool with fees.
        deploy(alice, apr, 0.1e18, 0.1e18, 0.5e18, governance);
        initialize(alice, apr, contribution);
        (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 totalGovFee
        ) = hyperdrive.calculateFeesOutGivenBondsIn(
                1 ether, // amountIn
                1 ether, // timeRemaining
                0.9 ether, // spotPrice
                1 ether // sharePrice
            );
        // curve fee = ((1 - p) * phi_curve * d_y * t) / c
        // ((1-.9)*.1*1*1)/1 = .01
        assertEq(totalCurveFee + totalFlatFee, .01 ether);

        assertEq(totalGovFee, .005 ether);

        (totalCurveFee, totalFlatFee, totalGovFee) = hyperdrive
            .calculateFeesOutGivenBondsIn(
                1 ether, // amountIn
                0, // timeRemaining
                0.9 ether, // spotPrice
                1 ether // sharePrice
            );
        assertEq(totalCurveFee + totalFlatFee, 0.1 ether);
        assertEq(totalGovFee, 0.05 ether);
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
            uint256 govCurveFee,
            uint256 govFlatFee
        ) = hyperdrive.calculateFeesInGivenBondsOut(
                1 ether, // amountOut
                1 ether, // timeRemaining
                0.9 ether, // spotPrice
                1 ether // sharePrice
            );
        assertEq(curveFee, .01 ether);
        assertEq(flatFee, 0 ether);
        assertEq(govCurveFee, .005 ether);
        assertEq(govFlatFee, 0 ether);

        (curveFee, flatFee, govCurveFee, govFlatFee) = hyperdrive
            .calculateFeesInGivenBondsOut(
                1 ether, // amountOut
                0, // timeRemaining
                0.9 ether, // spotPrice
                1 ether // sharePrice
            );
        assertEq(curveFee, 0 ether);
        assertEq(flatFee, 0.1 ether);
        assertEq(govCurveFee, 0 ether);
        assertEq(govFlatFee, 0.05 ether);
    }
}
