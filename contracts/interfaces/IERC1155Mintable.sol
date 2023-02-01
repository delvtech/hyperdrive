// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

interface IERC1155Mintable {
    /// @notice Allows the admin to mint tokens to a specified address.
    /// @param _target The target of the tokens.
    /// @param _id The ID of the token to mint.
    /// @param _amount The amount to send to the target.
    /// @param _data Extra data.
    function mint(
        address _target,
        uint256 _id,
        uint256 _amount,
        bytes memory _data
    ) external;

    /// @notice Allows the admin to burn tokens from a specified address.
    /// @param _source The source of the tokens.
    /// @param _id The ID of the token to burn.
    /// @param _amount The amount to burn from the receiver.
    function burn(address _source, uint256 _id, uint256 _amount) external;
}
