// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20 } from "./IERC20.sol";

interface IXRenzoDeposit {
    function xezETH() external view returns (IERC20);

    function getMintRate()
        external
        view
        returns (uint256 lastPrice, uint256 lastPriceTimestamp);
}
