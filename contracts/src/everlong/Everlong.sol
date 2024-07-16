// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { EverlongAdmin } from "contracts/src/everlong/EverlongAdmin.sol";
import { EverlongERC4626 } from "contracts/src/everlong/EverlongERC4626.sol";
import { EverlongPositions } from "contracts/src/everlong/EverlongPositions.sol";

contract Everlong is EverlongAdmin, EverlongERC4626, EverlongPositions {
    constructor(
        address underlying_,
        string memory name_,
        string memory symbol_
    )
        EverlongAdmin()
        EverlongERC4626(underlying_, name_, symbol_)
        EverlongPositions()
    {}
}
