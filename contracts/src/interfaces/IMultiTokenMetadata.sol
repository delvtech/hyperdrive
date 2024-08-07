// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IMultiTokenMetadata {
    /// @notice Gets the EIP712 permit typehash of the MultiToken.
    /// @return The EIP712 permit typehash of the MultiToken.
    // solhint-disable func-name-mixedcase
    function PERMIT_TYPEHASH() external view returns (bytes32);

    /// @notice Gets the EIP712 domain separator of the MultiToken.
    /// @return The EIP712 domain separator of the MultiToken.
    function domainSeparator() external view returns (bytes32);
}
