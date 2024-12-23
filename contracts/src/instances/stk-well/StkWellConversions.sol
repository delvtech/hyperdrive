// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

/// @author DELV
/// @title StkWellConversions
/// @notice The conversion logic for the  StkWell Hyperdrive integration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library StkWellConversions {
    /// @dev Convert an amount of vault shares to an amount of base.
    /// @dev Staked Well doesn't accrue interest, so the conversion from shares
    ///      to base is always 1:1.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        uint256 _shareAmount
    ) internal pure returns (uint256) {
        return _shareAmount;
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @dev Staked Well doesn't accrue interest, so the conversion from base to
    ///      shares is always 1:1.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        uint256 _baseAmount
    ) internal pure returns (uint256) {
        return _baseAmount;
    }
}
