// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { ERC20PresetFixedSupply } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import { Test } from "forge-std/Test.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { MockHyperdriveMath } from "test/mocks/MockHyperdriveMath.sol";
import "contracts/libraries/FixedPointMath.sol";

contract HyperdriveMathTest is Test {
    function setUp() public {}

    function test__calcSpotPrice() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        assertEq(
            hyperdriveMath.calculateSpotPrice(
                1 ether, // shareReserves
                1 ether, // bondReserves
                0 ether, // lpTotalSupply
                1 ether, // initalSharePrice
                1 ether, // timeRemaining
                1 ether // timeStretch
            ),
            1 ether // 1.0 spot price
        );

        assertApproxEqAbs(
            hyperdriveMath.calculateSpotPrice(
                1.1 ether, // shareReserves
                1 ether, // bondReserves
                0 ether, // lpTotalSupply
                1 ether, // initalSharePrice
                1 ether, // timeRemaining
                1 ether // timeStretch
            ),
            1.1 ether, // 1.1 spot price
            1 wei
        );
    }

    function test__calcAPRFromReserves() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        // equal reserves should make 0% APR
        assertEq(
            hyperdriveMath.calculateAPRFromReserves(
                1 ether, // shareReserves
                1 ether, // bondReserves
                0 ether, // lpTotalSupply
                1 ether, // initalSharePrice
                365 days, // positionDuration
                1 ether // timeStretch
            ),
            0 // 0% APR
        );

        // target a 10% APR
        assertApproxEqAbs(
            hyperdriveMath.calculateAPRFromReserves(
                1 ether, // shareReserves
                1.1 ether, // bondReserves
                0 ether, // lpTotalSupply
                1 ether, // initalSharePrice
                365 days, // positionDuration
                1 ether // timeStretch
            ),
            0.10 ether, // 10% APR
            2 wei // calculation rounds up 2 wei for some reason
        );
    }

    function test__calcFeesInGivenOut() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        (uint256 curveFee, uint256 flatFee) = hyperdriveMath
            .calculateFeesInGivenOut(
                1 ether, // amountOut
                1 ether, // timeRemaining
                0.9 ether, // spotPrice
                1 ether, // sharePrice
                0.1 ether, // curveFeePercent
                0.1 ether, // flatFeePercent
                true // isShareIn
            );
        assertEq(
            curveFee,
            .011111111111111111 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );

        (curveFee, flatFee) = hyperdriveMath.calculateFeesInGivenOut(
            1 ether, // amountOut
            1 ether, // timeRemaining
            0.9 ether, // spotPrice
            1 ether, // sharePrice
            0.1 ether, // curveFeePercent
            0.1 ether, // flatFeePercent
            false // isShareIn
        );
        assertEq(
            curveFee,
            .01 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );

        (curveFee, flatFee) = hyperdriveMath.calculateFeesInGivenOut(
            1 ether, // amountOut
            0, // timeRemaining
            0.9 ether, // spotPrice
            1 ether, // sharePrice
            0.1 ether, // curveFeePercent
            0.1 ether, // flatFeePercent
            true // isShareIn
        );
        assertEq(
            curveFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0.1 ether // ~ 0.011 ether or 10% of the price difference
        );

        (curveFee, flatFee) = hyperdriveMath.calculateFeesInGivenOut(
            1 ether, // amountOut
            0, // timeRemaining
            0.9 ether, // spotPrice
            1 ether, // sharePrice
            0.1 ether, // curveFeePercent
            0.1 ether, // flatFeePercent
            false // isShareIn
        );
        assertEq(
            curveFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0.1 ether // ~ 0.011 ether or 10% of the price difference
        );
    }

    function test__calcFeesOutGivenIn() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        (uint256 curveFee, uint256 flatFee) = hyperdriveMath
            .calculateFeesOutGivenIn(
                1 ether, // amountIn
                1 ether, // timeRemaining
                0.9 ether, // spotPrice
                1 ether, // sharePrice
                0.1 ether, // curveFeePercent
                0.1 ether, // flatFeePercent
                true // isShareIn
            );
        assertEq(
            curveFee,
            .011111111111111111 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );

        (curveFee, flatFee) = hyperdriveMath.calculateFeesOutGivenIn(
            1 ether, // amountIn
            1 ether, // timeRemaining
            0.9 ether, // spotPrice
            1 ether, // sharePrice
            0.1 ether, // curveFeePercent
            0.1 ether, // flatFeePercent
            false // isShareIn
        );
        assertEq(
            curveFee,
            .01 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );

        (curveFee, flatFee) = hyperdriveMath.calculateFeesOutGivenIn(
            1 ether, // amountIn
            0, // timeRemaining
            0.9 ether, // spotPrice
            1 ether, // sharePrice
            0.1 ether, // curveFeePercent
            0.1 ether, // flatFeePercent
            true // isShareIn
        );
        assertEq(
            curveFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0.1 ether, // ~ 0.011 ether or 10% of the price difference
            "test 1"
        );

        (curveFee, flatFee) = hyperdriveMath.calculateFeesOutGivenIn(
            1 ether, // amountIn
            0, // timeRemaining
            0.9 ether, // spotPrice
            1 ether, // sharePrice
            0.1 ether, // curveFeePercent
            0.1 ether, // flatFeePercent
            false // isShareIn
        );
        assertEq(
            curveFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0.1 ether, // ~ 0.011 ether or 10% of the price difference
            "test 2"
        );
    }
}
