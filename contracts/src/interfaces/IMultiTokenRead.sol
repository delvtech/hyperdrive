// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IMultiTokenRead {
    /// @notice Gets the decimals of the MultiToken.
    /// @return The decimals of the MultiToken.
    function decimals() external view returns (uint8);

    /// @notice Gets the name of the MultiToken.
    /// @param tokenId The sub-token ID.
    /// @return The name of the MultiToken.
    function name(uint256 tokenId) external view returns (string memory);

    /// @notice Gets the symbol of the MultiToken.
    /// @param tokenId The sub-token ID.
    /// @return The symbol of the MultiToken.
    function symbol(uint256 tokenId) external view returns (string memory);

    /// @notice Gets the total supply of the MultiToken.
    /// @param tokenId The sub-token ID.
    /// @return The total supply of the MultiToken.
    function totalSupply(uint256 tokenId) external view returns (uint256);

    /// @notice Gets the approval-for-all status of a spender on behalf of an
    ///         owner.
    /// @param owner The owner of the tokens.
    /// @param spender The spender of the tokens.
    /// @return The approval-for-all status of the spender for the owner.
    function isApprovedForAll(
        address owner,
        address spender
    ) external view returns (bool);

    /// @notice Gets the allowance of a spender for a sub-token.
    /// @param tokenId The sub-token ID.
    /// @param owner The owner of the tokens.
    /// @param spender The spender of the tokens.
    /// @return The allowance of the spender for the owner.
    function perTokenApprovals(
        uint256 tokenId,
        address owner,
        address spender
    ) external view returns (uint256);

    /// @notice Gets the balance of a spender for a sub-token.
    /// @param tokenId The sub-token ID.
    /// @param owner The owner of the tokens.
    /// @return The balance of the owner.
    function balanceOf(
        uint256 tokenId,
        address owner
    ) external view returns (uint256);

    /// @notice Gets multiple accounts' balances for multiple token IDs.
    /// @param _accounts Array of addresses to check balances for.
    /// @param _ids Array of token IDs to check balances of.
    /// @return Array of token balances.
    function balanceOfBatch(
        address[] calldata _accounts,
        uint256[] calldata _ids
    ) external view returns (uint256[] memory);

    /// @notice Gets the permit nonce for an account.
    /// @param _owner The owner of the tokens.
    /// @return The permit nonce of the owner.
    function nonces(address _owner) external view returns (uint256);

    /// @notice Returns whether or not an interface is supported.
    /// @param _interfaceId The ID of the interface.
    /// @return A flag indicating whether or not the interface is supported.
    function supportsInterface(
        bytes4 _interfaceId
    ) external pure returns (bool);
}
