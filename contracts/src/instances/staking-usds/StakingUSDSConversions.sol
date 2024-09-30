// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

/// @author DELV
/// @title StakingUSDSConversions
/// @notice The conversion logic for the  StakingUSDS Hyperdrive integration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library StakingUSDSConversions {
    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @dev StakingUSDS doesn't accrue interest, so the conversion from shares
    ///      to base is always 1:1.
    /// @return The base amount.
    function convertToBase(
        uint256 _shareAmount
    ) external pure returns (uint256) {
        return _shareAmount;
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @dev StakingUSDS doesn't accrue interest, so the conversion from base to
    ///      shares is always 1:1.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        uint256 _baseAmount
    ) external pure returns (uint256) {
        return _baseAmount;
    }
}
