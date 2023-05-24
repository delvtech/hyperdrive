// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { BondWrapper } from "../src/BondWrapper.sol";
import { IHyperdrive } from "../src/interfaces/IHyperdrive.sol";
import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ERC20Permit } from "../src/libraries/ERC20Permit.sol";

contract MockBondWrapper is BondWrapper {
    constructor(
        IHyperdrive _hyperdrive,
        IERC20 _token,
        uint256 _mintPercent,
        string memory name_,
        string memory symbol_
    ) BondWrapper(_hyperdrive, _token, _mintPercent, name_, symbol_) {}

    function mint(address destination, uint256 amount) external {
        _mint(destination, amount);
    }

    function burn(address destination, uint256 amount) external {
        _burn(destination, amount);
    }

    function setDeposits(
        address user,
        uint256 assetId,
        uint256 amount
    ) external {
        deposits[user][assetId] = amount;
    }

    function setBalanceOf(address user, uint256 amount) external {
        balanceOf[user] = amount;
    }
}
