// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

interface IMultiTokenMetadata {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
