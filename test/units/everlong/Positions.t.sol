// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IEverlongAdmin } from "contracts/src/interfaces/IEverlongAdmin.sol";
import { EverlongTest } from "test/utils/EverlongTest.sol";

contract EverlongPositionTest is EverlongTest {
    function test_no_positions_after_fresh_deploy() external {
        deployEverlong(alice);
        assertEq(everlong.getNumberOfPositions(), 0);
    }
}
