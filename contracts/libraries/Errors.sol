/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

/// @author Delve
/// @title Errors
/// @notice A library containing the errors used in this codebase.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library Errors {
    /// ##################
    /// ### Hyperdrive ###
    /// ##################
    error BaseBufferExceedsShareReserves();
    error InvalidCheckpointTime();
    error InvalidCheckpointDuration();
    error InvalidMaturityTime();
    error PoolAlreadyInitialized();
    error TransferFailed();
    error UnexpectedAssetId();
    error ZeroAmount();

    /// ######################
    /// ### ERC20Forwarder ###
    /// ######################
    error BatchInputLengthMismatch();
    error ExpiredDeadline();
    error InvalidSignature();
    error InvalidERC20Bridge();
    error RestrictedZeroAddress();

    /// ######################
    /// ### FixedPointMath ###
    /// ######################
    error FixedPointMath_AddOverflow();
    error FixedPointMath_SubOverflow();
    error FixedPointMath_InvalidExponent();
    error FixedPointMath_NegativeOrZeroInput();
    error FixedPointMath_NegativeInput();

    /// ###############
    /// ### AssetId ###
    /// ###############
    error InvalidTimestamp();

    /// #####################
    /// ### BondWrapper ###
    /// #####################

    error AlreadyClosed();
    error BondMatured();
    error BondNotMatured();
    error InsufficientPrice();
}
