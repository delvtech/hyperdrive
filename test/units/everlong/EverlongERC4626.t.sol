// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IEverlongAdmin } from "contracts/src/interfaces/IEverlongAdmin.sol";
import { EverlongTest } from "test/utils/EverlongTest.sol";

contract EverlongERC4626Test is EverlongTest {
    function test_constructor_sets_asset_name_symbol() external {
        address underlying = address(hyperdrive);
        string memory name = "TEST_NAME";
        string memory symbol = "TEST_SYMBOL";
        deployEverlong(alice, underlying, name, symbol);
        assertEq(everlong.asset(), underlying);
        assertEq(everlong.name(), name);
        assertEq(everlong.symbol(), symbol);
    }
}
