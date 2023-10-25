// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AssetId } from "../libraries/AssetId.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IMultiTokenRead } from "../interfaces/IMultiTokenRead.sol";
import { MultiTokenStorage } from "./MultiTokenStorage.sol";

/// @author DELV
/// @title MultiTokenDataProvider
/// @notice The MultiToken data provider.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MultiTokenDataProvider is MultiTokenStorage, IMultiTokenRead {
    // solhint-disable no-empty-blocks
    /// @notice Initializes the MultiToken's data provider.
    /// @param _linkerCodeHash_ The hash of the erc20 linker contract deploy code
    /// @param _factory_ The factory which is used to deploy the linking contracts
    constructor(
        bytes32 _linkerCodeHash_,
        address _factory_
    ) MultiTokenStorage(_linkerCodeHash_, _factory_) {}

    /// @notice Gets the code hash of the erc20 linker contract.
    /// @return The code hash.
    function linkerCodeHash() external view returns (bytes32) {
        _revert(abi.encode(_linkerCodeHash));
    }

    /// @notice Gets the factory which is used to deploy the linking contracts.
    /// @return The linking factory.
    function factory() external view returns (address) {
        _revert(abi.encode(_factory));
    }

    /// @notice Gets an account's balance of a sub-token.
    /// @param tokenId The sub-token id.
    /// @param account The account.
    /// @return The balance.
    function balanceOf(
        uint256 tokenId,
        address account
    ) external view override returns (uint256) {
        _revert(abi.encode(_balanceOf[tokenId][account]));
    }

    /// @notice Gets the total supply of a sub-token.
    /// @param tokenId The sub-token id.
    /// @return The total supply.
    function totalSupply(
        uint256 tokenId
    ) external view override returns (uint256) {
        _revert(abi.encode(_totalSupply[tokenId]));
    }

    /// @notice Gets the approval status of an operator for an account.
    /// @param account The account.
    /// @param operator The operator.
    /// @return The approval status.
    function isApprovedForAll(
        address account,
        address operator
    ) external view override returns (bool) {
        _revert(abi.encode(_isApprovedForAll[account][operator]));
    }

    /// @notice Gets the approval status of an operator for an account.
    /// @param tokenId The sub-token id.
    /// @param account The account.
    /// @param spender The spender.
    /// @return The approval status.
    function perTokenApprovals(
        uint256 tokenId,
        address account,
        address spender
    ) external view override returns (uint256) {
        _revert(abi.encode(_perTokenApprovals[tokenId][account][spender]));
    }

    /// @notice Gets the name of a sub-token.
    /// @param tokenId The sub-token id.
    /// @return The name.
    function name(
        uint256 tokenId
    ) external pure override returns (string memory) {
        _revert(abi.encode(AssetId.assetIdToName(tokenId)));
    }

    /// @notice Gets the symbol of a sub-token.
    /// @param tokenId The sub-token id.
    /// @return The symbol.
    function symbol(
        uint256 tokenId
    ) external pure override returns (string memory) {
        _revert(abi.encode(AssetId.assetIdToSymbol(tokenId)));
    }

    /// @notice Gets the permitForAll signature nonce for an account.
    /// @param account The account.
    /// @return The signature nonce.
    function nonces(address account) external view override returns (uint256) {
        _revert(abi.encode(_nonces[account]));
    }

    /// @dev Reverts with the provided bytes. This is useful in getters used
    ///      with the force-revert delegatecall pattern.
    /// @param _bytes The bytes to revert with.
    function _revert(bytes memory _bytes) internal pure {
        revert IHyperdrive.ReturnData(_bytes);
    }
}
