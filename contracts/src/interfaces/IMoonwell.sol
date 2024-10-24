// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "./IERC20.sol";

/// @author DELV
/// @title IMoonwell
/// @notice The interface file for Moonwell
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract IMoonwell is IERC20 {

    /// @notice Sender supplies assets into the market and receives mTokens in exchange
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param mintAmount The amount of the underlying asset to supply
    /// @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
    function mint(uint256) external view returns (uint256);

    /// @notice Sender redeems mTokens in exchange for the underlying asset
    /// @dev Accrues interest whether or not the operation succeeds, unless reverted
    /// @param redeemTokens The number of mTokens to redeem into underlying
    /// @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
    function redeem(uint256) external view returns (uint256);

    function underlying(address) external view returns (address);

    /// @notice Total amount of outstanding borrows of the underlying in this market
    function totalBorrows() external view returns (uint256);

    /// @notice Total amount of reserves of the underlying held in this market
    function totalReserves() external view returns (uint256);

    /// @notice Total number of tokens in circulation
    function totalSupply() external view returns (uint256);
}