// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20 } from "./IERC20.sol";

interface ILido is IERC20 {
    /// @notice Submits ether to stETH to be staked.
    /// @param _referral The referral address that should get credit in Lido's
    ///        referral program.
    /// @return The amount of stETH shares that were minted.
    function submit(address _referral) external payable returns (uint256);

    /// @notice Transfers stETH shares from the caller to a recipient.
    /// @param _recipient The recipient of the tokens.
    /// @param _sharesAmount The amount of stETH shares that will be transferred.
    /// @return The amount of stETH tokens that were transferred.
    function transferShares(
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256);

    /// @notice Transfers stETH shares from an owner to a recipient. This draws
    ///         from the spender's allowance.
    /// @param _sender The owner of the tokens.
    /// @param _recipient The recipient of the tokens.
    /// @param _sharesAmount The amount of tokens that will be transferred.
    /// @return The amount of stETH tokens transferred.
    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256);

    /// @notice Calculates the amount of stETH shares an amount of stETH tokens
    ///         are currently worth.
    /// @param _ethAmount The amount of stETH tokens to convert.
    /// @return The amount of stETH shares that the stETH tokens are worth.
    function getSharesByPooledEth(
        uint256 _ethAmount
    ) external view returns (uint256);

    /// @notice Calculates the amount of stETH tokens an amount of stETH shares
    ///         are currently worth.
    /// @param _sharesAmount The amount of stETH shares to convert.
    /// @return The amount of stETH tokens that the stETH shares are worth.
    function getPooledEthByShares(
        uint256 _sharesAmount
    ) external view returns (uint256);

    /// @notice Gets the total amount of ether that is buffered and waiting
    ///         to be staked underlying stETH.
    /// @return The total amount of buffered ether.
    function getBufferedEther() external view returns (uint256);

    /// @notice Gets the total amount of pooled ether underlying stETH.
    /// @return The total amount of pooled ether.
    function getTotalPooledEther() external view returns (uint256);

    /// @notice Gets the total amount of stETH shares.
    /// @return The total amount of stETH shares.
    function getTotalShares() external view returns (uint256);

    /// @notice Gets the amount of shares owned by an account.
    /// @param _account The owner of the shares.
    //// @return The amount of shares owned by the account.
    function sharesOf(address _account) external view returns (uint256);
}
