// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20 } from "./IERC20.sol";

interface IWrappedERC20 is IERC20 {
    function wrap(uint256 _amount) external returns (uint256);
}
