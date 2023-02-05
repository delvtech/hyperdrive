// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./IMultiToken.sol";

interface IForwarderFactory {
    function getDeployDetails() external returns (IMultiToken, uint256);
}
