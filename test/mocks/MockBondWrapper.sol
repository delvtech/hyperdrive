// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { BondWrapper } from "contracts/BondWrapper.sol";
import { IHyperdrive } from "contracts/interfaces/IHyperdrive.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ERC20Permit } from "contracts/libraries/ERC20Permit.sol";

contract MockBondWrapper is BondWrapper {
    constructor(
        IHyperdrive _hyperdrive,
        IERC20 _token,
        uint256 _mintPercent,
        string memory name_,
        string memory symbol_
    ) BondWrapper(_hyperdrive, _token, _mintPercent, name_, symbol_) {}

    function __setMintPercent(uint256 _mintPercent) external {
        mintPercent = _mintPercent;
    }
}
