/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

/// @author DELV
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
    error InvalidApr();
    error InvalidBaseToken();
    error InvalidCheckpointTime();
    error InvalidCheckpointDuration();
    error InvalidInitialSharePrice();
    error InvalidMaturityTime();
    error InvalidPositionDuration();
    error InvalidFeeAmounts();
    error NegativeInterest();
    error OutputLimit();
    error Paused();
    error PoolAlreadyInitialized();
    error TransferFailed();
    error UnexpectedAssetId();
    error UnexpectedSender();
    error UnsupportedToken();
    error ZeroAmount();
    error ZeroLpTotalSupply();

    /// ############
    /// ### TWAP ###
    /// ############
    error QueryOutOfRange();

    /// ####################
    /// ### DataProvider ###
    /// ####################
    error UnexpectedSuccess();

    /// ###############
    /// ### Factory ###
    /// ###############
    error Unauthorized();
    error InvalidContribution();
    error InvalidToken();

    /// ######################
    /// ### ERC20Forwarder ###
    /// ######################
    error BatchInputLengthMismatch();
    error ExpiredDeadline();
    error InvalidSignature();
    error InvalidERC20Bridge();
    error RestrictedZeroAddress();

    /// #####################
    /// ### BondWrapper ###
    /// #####################
    error AlreadyClosed();
    error BondMatured();
    error BondNotMatured();
    error InsufficientPrice();

    /// ###############
    /// ### AssetId ###
    /// ###############
    error InvalidTimestamp();

    /// ######################
    /// ### FixedPointMath ###
    /// ######################
    error FixedPointMath_AddOverflow();
    error FixedPointMath_SubOverflow();
    error FixedPointMath_InvalidExponent();
    error FixedPointMath_NegativeOrZeroInput();
    error FixedPointMath_NegativeInput();
}
