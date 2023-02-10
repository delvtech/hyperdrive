// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { YieldSpaceMath } from "contracts/libraries/YieldSpaceMath.sol";

contract YieldSpaceMathTest is Test {
    function test__calculateOutGivenIn_1() public {
        assertEq(
            YieldSpaceMath.calculateOutGivenIn(
                56.79314253e18, // shareReserves
                62.38101813e18, // bondReserves
                119.1741606776616e18, // bondReserveAdjustment
                5.03176076e18, // amountOut
                1e18 - 0.08065076081220067e18, // t
                1e18, // c
                1e18, // mu
                true // isBondIn
            ),
            5.500250311701939082e18
        );
    }

    function test__calculateOutGivenIn_2() public {
        assertEq(
            YieldSpaceMath.calculateOutGivenIn(
                61.824903300361854e18, // shareReserves
                56.92761678068477e18, // bondReserves
                119.1741606776616e18, // bondReserveAdjustment
                5.500250311701939e18, // amountOut
                1e18 - 0.08065076081220067e18, // t
                1e18, // c
                1e18, // mu
                false // isBondIn
            ),
            5.031654806080805188e18
        );
    }
}
