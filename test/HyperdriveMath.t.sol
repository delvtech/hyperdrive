// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { ERC20PresetFixedSupply } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import { Test } from "forge-std/Test.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import "contracts/libraries/FixedPointMath.sol";

contract HyperdriveMathTest is Test {
    function setUp() public {}

    function test__calcSpotPrice() public {
        assertEq(
            HyperdriveMath.calculateSpotPrice(
                1 ether, // shareReserves
                1 ether, // bondReserves
                0 ether, // lpTotalSupply
                1 ether, // initalSharePrice
                365 days, // timeRemaining
                365 days, // positionDuration
                1 ether // timeStretch
            ),
            1 ether // 1.0 spot price
        );

        assertApproxEqAbs(
            HyperdriveMath.calculateSpotPrice(
                1.1 ether, // shareReserves
                1 ether, // bondReserves
                0 ether, // lpTotalSupply
                1 ether, // initalSharePrice
                365 days, // timeRemaining
                365 days, // positionDuration
                1 ether // timeStretch
            ),
            1.1 ether, // 1.1 spot price
            1 wei
        );
    }

    function test__calcAPRFromReserves() public {
        // equal reserves should make 0% APR
        assertEq(
            HyperdriveMath.calculateAPRFromReserves(
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
            HyperdriveMath.calculateAPRFromReserves(
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
        assertEq(
            HyperdriveMath.calculateFeesInGivenOut(
                365 days, // timeRemaining
                365 days, // positionDuration
                0.9 ether, // spotPrice
                0.1 ether, // feePercent
                1 ether, // sharePrice
                1 ether, // amountOut
                true // isBaseOut
            ),
            .011111111111111111 ether // ~ 0.011 ether or 10% of the price difference
        );

        assertEq(
            HyperdriveMath.calculateFeesInGivenOut(
                365 days, // timeRemaining
                365 days, // positionDuration
                0.9 ether, // spotPrice
                0.1 ether, // feePercent
                1 ether, // sharePrice
                1 ether, // amountOut
                false // isBaseOut
            ),
            0.01 ether // 0.01 ether or 10% of the price difference
        );
    }

    function test__calcFeesOutGivenIn() public {
        assertEq(
            HyperdriveMath.calculateFeesOutGivenIn(
                365 days, // timeRemaining
                365 days, // positionDuration
                0.9 ether, // spotPrice
                0.1 ether, // feePercent
                1 ether, // sharePrice
                1 ether, // amountOut
                true // isBaseIn
            ),
            .011111111111111111 ether // ~ 0.011 ether or 10% of the price difference
        );

        assertEq(
            HyperdriveMath.calculateFeesOutGivenIn(
                365 days, // timeRemaining
                365 days, // positionDuration
                0.9 ether, // spotPrice
                0.1 ether, // feePercent
                1 ether, // sharePrice
                1 ether, // amountOut
                false // isBaseIn
            ),
            0.01 ether // 0.01 ether or 10% of the price difference
        );
    }
}
