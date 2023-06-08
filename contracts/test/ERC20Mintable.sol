// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
//import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";

contract ERC20Mintable is ERC20 {
    constructor() ERC20("Base", "BASE") {}

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function mint(address destination, uint256 amount) external {
        _mint(destination, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burn(address destination, uint256 amount) external {
        _burn(destination, amount);
    }
}
