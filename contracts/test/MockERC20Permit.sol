// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { ERC20 } from "solmate/tokens/ERC20.sol";

contract MockERC20Permit is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_
    )
        // 18 decimals hardcoded to match BondWrapper
        ERC20(name_, symbol_, 18)
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
