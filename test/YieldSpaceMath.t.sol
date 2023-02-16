// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { YieldSpaceMath } from "contracts/libraries/YieldSpaceMath.sol";
import "forge-std/console2.sol";

contract YieldSpaceMathTest is Test {
    function test__calculateOutGivenIn() public {
        uint256 result1 = YieldSpaceMath.calculateOutGivenIn(
                61.824903300361854e18, // shareReserves
                56.92761678068477e18, // bondReserves
                119.1741606776616e18, // bondReserveAdjustment
                5.500250311701939e18, // amountIn
                1e18 - 0.08065076081220067e18, // stretchedTimeElapsed
                1e18, // c
                1e18, // mu
                true // isBondIn
            );
        assertEq(
            result1,
            5.955718322566968926e18
        );

        uint256 result2 = YieldSpaceMath.calculateOutGivenIn(
                61.824903300361854e18, // shareReserves
                56.92761678068477e18, // bondReserves
                119.1741606776616e18, // bondReserveAdjustment
                5.500250311701939e18, // amountIn
                1e18 - 0.08065076081220067e18, // stretchedTimeElapsed
                1e18, // c
                1e18, // mu
                false // isBondIn
            );
        assertEq(
            result2,
            5.031654806080805188e18
        );

        console2.log("result1", result1);
        console2.log("result2", result2);
    }
}
