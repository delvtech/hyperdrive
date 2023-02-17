// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import "test/mocks/MockYieldSpaceMath.sol";

contract YieldSpaceMathTest is Test {

    function test__calculateOutGivenIn() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 result1 = yieldSpaceMath.calculateOutGivenIn(
            61.824903300361854e18, // shareReserves
            56.92761678068477e18, // bondReserves
            119.1741606776616e18, // bondReserveAdjustment
            5.500250311701939e18, // amountIn
            1e18 - 0.08065076081220067e18, // stretchedTimeElapsed
            1e18, // c
            1e18, // mu
            true // isBondIn
        );
        assertEq(result1, 5.955718322566968926e18);

        uint256 result2 = yieldSpaceMath.calculateOutGivenIn(
            61.824903300361854e18, // shareReserves
            56.92761678068477e18, // bondReserves
            119.1741606776616e18, // bondReserveAdjustment
            5.500250311701939e18, // amountIn
            1e18 - 0.08065076081220067e18, // stretchedTimeElapsed
            1e18, // c
            1e18, // mu
            false // isBondIn
        );
        assertEq(result2, 5.031654806080804961e18);
    }

    function test__calculateInGivenOut() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 result1 = yieldSpaceMath.calculateInGivenOut(
            61.824903300361854e18, // shareReserves
            56.92761678068477e18, // bondReserves
            119.1741606776616e18, // bondReserveAdjustment
            5.500250311701939e18, // amountOut
            1e18 - 0.08065076081220067e18, // stretchedTimeElapsed
            1e18, // c
            1e18, // mu
            true // isBaseOut
        );
        assertEq(result1, 6.015131552181907864e18);

        uint256 result2 = yieldSpaceMath.calculateInGivenOut(
            61.824903300361854e18, // shareReserves
            56.92761678068477e18, // bondReserves
            119.1741606776616e18, // bondReserveAdjustment
            5.500250311701939e18, // amountOut
            1e18 - 0.08065076081220067e18, // stretchedTimeElapsed
            1e18, // c
            1e18, // mu
            false // isBaseOut
        );
        assertEq(result2, 5.077749727267331547e18);
    }
}
