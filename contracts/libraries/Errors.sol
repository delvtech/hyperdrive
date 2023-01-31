/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

library ElementError {
    /// ##################
    /// ### Hyperdrive ###
    /// ##################
    error PoolAlreadyInitialized();

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
