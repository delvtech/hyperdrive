// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { BondWrapper } from "../src/BondWrapper.sol";
import { IHyperdrive } from "../src/interfaces/IHyperdrive.sol";
import { IERC20 } from "../src/interfaces/IERC20.sol";
import { ERC20Permit } from "../src/libraries/ERC20Permit.sol";

contract MockBondWrapper is BondWrapper {
    constructor(
        IHyperdrive _hyperdrive,
        IERC20 _token,
        uint256 _mintPercent,
        string memory name_,
        string memory symbol_
    ) BondWrapper(_hyperdrive, _token, _mintPercent, name_, symbol_) {}
}
