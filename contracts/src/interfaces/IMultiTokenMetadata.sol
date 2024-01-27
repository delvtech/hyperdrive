// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

interface IMultiTokenMetadata {
    // solhint-disable func-name-mixedcase
    function PERMIT_TYPEHASH() external view returns (bytes32);

    // solhint-disable func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
