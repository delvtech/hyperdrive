// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IMultiToken } from "./IMultiToken.sol";

interface IForwarderFactory {
    function getDeployDetails() external returns (IMultiToken, uint256);
}
