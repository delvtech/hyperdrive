// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import "test/mocks/MockYieldSpaceMath.sol";

contract YieldSpaceMathTest is Test {
    // calculateInGivenOut true
    function test__calculateBondsInGivenSharesOut() public {
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 result = yieldSpaceMath.calculateBondsInGivenSharesOut(
            61.824903300361854e18, // shareReserves
            56.92761678068477e18, // bondReserves
            119.1741606776616e18, // bondReserveAdjustment
            5.500250311701939e18, // amountOut
            1e18 - 0.08065076081220067e18, // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        assertEq(result, 6.015131552181907864e18);
    }

    // calculateOutGivenIn true
    function test__calculateBondsOutGivenSharesIn() public {
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 result = yieldSpaceMath.calculateBondsOutGivenSharesIn(
            61.824903300361854e18, // shareReserves
            56.92761678068477e18, // bondReserves
            119.1741606776616e18, // bondReserveAdjustment
            5.500250311701939e18, // amountIn
            1e18 - 0.08065076081220067e18, // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        assertEq(result, 5.955718322566968926e18);
    }

    // calculateInGivenOut false
    function test__calculateSharesInGivenBondsOut() public {
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 result = yieldSpaceMath.calculateSharesInGivenBondsOut(
            61.824903300361854e18, // shareReserves
            56.92761678068477e18, // bondReserves
            119.1741606776616e18, // bondReserveAdjustment
            5.500250311701939e18, // amountOut
            1e18 - 0.08065076081220067e18, // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        assertEq(result, 5.077749727267331547e18);
    }

    // calculateOutGivenIn false
    function test__calculateSharesOutGivenBondsIn() public {
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 result = yieldSpaceMath.calculateSharesOutGivenBondsIn(
            61.824903300361854e18, // shareReserves
            56.92761678068477e18, // bondReserves
            119.1741606776616e18, // bondReserveAdjustment
            5.500250311701939e18, // amountIn
            1e18 - 0.08065076081220067e18, // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        assertEq(result, 5.031654806080804961e18);
    }



}
