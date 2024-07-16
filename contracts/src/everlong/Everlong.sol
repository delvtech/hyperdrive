// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { EverlongAdmin } from "./EverlongAdmin.sol";
import { EverlongERC4626 } from "./EverlongERC4626.sol";
import { EverlongPositions } from "./EverlongPositions.sol";

contract Everlong is EverlongAdmin, EverlongERC4626, EverlongPositions {
    constructor(
        address underlying_,
        string memory name_,
        string memory symbol_
    ) EverlongERC4626(underlying_, name_, symbol_) {}
}
