// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { FixedPointMath } from "../../libraries/FixedPointMath.sol";
import { IPSM } from "../../interfaces/IPSM.sol";
import { IRateProvider } from "../../interfaces/IRateProvider.sol";

/// @author DELV
/// @title SavingsUSDSL2Conversions
/// @notice The conversion logic for the  SavingsUSDSL2 Hyperdrive integration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library SavingsUSDSL2Conversions {
    using FixedPointMath for uint256;
    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _PSM The PSM contract.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IPSM _PSM,
        uint256 _shareAmount
    ) internal view returns (uint256) {
        /// Sky's internal accounting uses RAY units (1e27), so we want to
        /// ensure that we're using the same precision.
        return
            _shareAmount.mulDivDown(
                IRateProvider(_PSM.rateProvider()).getConversionRate(),
                1e27
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
        /// Sky's internal accounting uses RAY units (1e27), so we want to
        /// ensure that we're using the same precision.
        return
            _baseAmount.mulDivDown(
                1e27,
                IRateProvider(_PSM.rateProvider()).getConversionRate()
            );
    }
}
