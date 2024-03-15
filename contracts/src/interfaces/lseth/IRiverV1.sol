// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ISharesManagerV1 } from "./ISharesManagerV1.sol";

/// @title River Interface (v1)
/// @author Kiln
/// @notice The main system interface
interface IRiverV1 is ISharesManagerV1 {
    /// @notice Thrown when the amount received from the Withdraw contract doe not match the requested amount
    /// @param requested The amount that was requested
    /// @param received The amount that was received
    error InvalidPulledClFundsAmount(uint256 requested, uint256 received);

    /// @notice The computed amount of shares to mint is 0
    error ZeroMintedShares();

    /// @notice The access was denied
    /// @param account The account that was denied
    error Denied(address account);
}
