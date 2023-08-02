// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;
import {IStETH, ERC20} from "../../lib/yield-daddy/src/lido/external/IStETH.sol";

contract StETH is IStETH {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}

    uint256 private _totalShares;

    function getTotalShares() external override view returns (uint256) {
        return _totalShares;
    }
}
