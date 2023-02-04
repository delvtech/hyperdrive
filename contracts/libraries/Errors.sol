/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

/// @author Delve
/// @title HyperdriveError
/// @notice A library containing the errors used in the Hyperdrive system.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library HyperdriveError {
    /// ##################
    /// ### Hyperdrive ###
    /// ##################
    error AssetIDCorruption();
    error BaseBufferExceedsShareReserves();
    error BondBufferExceedsBondReserves();
    error InvalidMaturityTime();
    error InvalidShortID();
    error PoolAlreadyInitialized();
    error TransferFailed();
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

    /// ######################
    /// ### HyperdriveMath ###
    /// ######################
    error HyperdriveMath_BaseWithNonzeroTime();
}
