// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { IPSM } from "../../interfaces/IPSM.sol";

/// @author DELV
/// @title SavingsUSDSBaseConversions
/// @notice The conversion logic for the  SavingsUSDSBase Hyperdrive integration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library SavingsUSDSBaseConversions {
    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _PSM The PSM contract.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IPSM _PSM,
        uint256 _shareAmount
    ) internal view returns (uint256) {
        return _PSM.previewSwapExactOut(
            _PSM.susds(),
            _PSM.usds(),
            _shareAmount
        );
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _PSM The PSM contract.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IPSM _PSM,
        uint256 _baseAmount
    ) internal view returns (uint256) {
        return _PSM.previewSwapExactIn(
            _PSM.usds(),
            _PSM.susds(),
            _baseAmount
        );
    }
}