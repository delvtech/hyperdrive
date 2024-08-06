// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IERC20 {
    /// @notice Emitted when tokens are transferred from one account to another.
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when an owner changes the approval for a spender.
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    /// @notice Updates the allowance of a spender on behalf of the sender.
    /// @param spender The account with the allowance.
    /// @param amount The new allowance of the spender.
    /// @return A flag indicating whether or not the approval succeeded.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Transfers tokens from the sender's account to another account.
    /// @param to The recipient of the tokens.
    /// @param amount The amount of tokens that will be transferred.
    /// @return A flag indicating whether or not the transfer succeeded.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Transfers tokens from an owner to a recipient. This draws from
    ///         the sender's allowance.
    /// @param from The owner of the tokens.
    /// @param to The recipient of the tokens.
    /// @param amount The amount of tokens that will be transferred.
    /// @return A flag indicating whether or not the transfer succeeded.
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    /// @notice Gets the token's name.
    /// @return The token's name.
    function name() external view returns (string memory);

    /// @notice Gets the token's symbol.
    /// @return The token's symbol.
    function symbol() external view returns (string memory);

    /// @notice Gets the token's decimals.
    /// @return The token's decimals.
    function decimals() external view returns (uint8);

    /// @notice Gets the token's total supply.
    /// @return The token's total supply.
    function totalSupply() external view returns (uint256);

    /// @notice Gets the allowance of a spender for an owner.
    /// @param owner The owner of the tokens.
    /// @param spender The spender of the tokens.
    /// @return The allowance of the spender for the owner.
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /// @notice Gets the balance of an account.
    /// @param account The owner of the tokens.
    /// @return The account's balance.
    function balanceOf(address account) external view returns (uint256);
}
