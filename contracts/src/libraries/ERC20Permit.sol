// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20Permit } from "../interfaces/IERC20Permit.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";

// This default erc20 library is designed for max efficiency and security.
// WARNING: By default it does not include totalSupply which breaks the ERC20 standard
//          to use a fully standard compliant ERC20 use 'ERC20PermitWithSupply"
contract ERC20Permit is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 _decimals
    ) ERC20(name_, symbol_, _decimals) {}
}
