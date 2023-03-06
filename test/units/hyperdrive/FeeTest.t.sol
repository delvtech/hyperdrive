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
        (uint256 totalFee, uint256 totalGovFee) = hyperdrive
            .calculateFeesOutGivenBondsIn(
                1 ether, // amountIn
                1 ether, // timeRemaining
                0.9 ether, // spotPrice
                1 ether // sharePrice
            );
        assertEq(totalFee, .01 ether);

        assertEq(totalGovFee, .005 ether);

        (totalFee, totalGovFee) = hyperdrive.calculateFeesOutGivenBondsIn(
            1 ether, // amountIn
            0, // timeRemaining
            0.9 ether, // spotPrice
            1 ether // sharePrice
        );
        assertEq(totalFee, 0.1 ether);
        assertEq(totalGovFee, 0.05 ether);
    }

    function test_calculateFeesInGivenBondsOut() public {
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
