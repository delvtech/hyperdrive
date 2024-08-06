// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20 } from "./IERC20.sol";

/// @title Shares Manager Interface (v1)
/// @author Kiln
/// @notice This interface exposes methods to handle the shares of the depositor and the ERC20 interface
interface ISharesManagerV1 is IERC20 {
    /// @notice Retrieve the total token supply
    /// @return The total supply in shares
    function totalSupply() external view returns (uint256);

    /// @notice Retrieve the total underlying asset supply
    /// @return The total underlying asset supply
    function totalUnderlyingSupply() external view returns (uint256);

    /// @notice Retrieve the balance of an account
    /// @param _owner Address to be checked
    /// @return The balance of the account in shares
    function balanceOf(address _owner) external view returns (uint256);

    /// @notice Retrieve the underlying asset balance of an account
    /// @param _owner Address to be checked
    /// @return The underlying balance of the account
    function balanceOfUnderlying(
        address _owner
    ) external view returns (uint256);

    /// @notice Retrieve the underlying asset balance from an amount of shares
    /// @param _shares Amount of shares to convert
    /// @return The underlying asset balance represented by the shares
    function underlyingBalanceFromShares(
        uint256 _shares
    ) external view returns (uint256);

    /// @notice Retrieve the shares count from an underlying asset amount
    /// @param _underlyingAssetAmount Amount of underlying asset to convert
    /// @return The amount of shares worth the underlying asset amopunt
    function sharesFromUnderlyingBalance(
        uint256 _underlyingAssetAmount
    ) external view returns (uint256);

    /// @notice Performs a transfer from the message sender to the provided account
    /// @param _to Address receiving the tokens
    /// @param _value Amount of shares to be sent
    /// @return True if success
    function transfer(address _to, uint256 _value) external returns (bool);

    /// @notice Performs a transfer between two recipients
    /// @param _from Address sending the tokens
    /// @param _to Address receiving the tokens
    /// @param _value Amount of shares to be sent
    /// @return True if success
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool);

    /// @notice Approves an account for future spendings
    /// @dev An approved account can use transferFrom to transfer funds on behalf of the token owner
    /// @param _spender Address that is allowed to spend the tokens
    /// @param _value The allowed amount in shares, will override previous value
    /// @return True if success
    function approve(address _spender, uint256 _value) external returns (bool);
}
