// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "../../interfaces/IERC20.sol";
import { IRiverV1 } from "../../interfaces/IRiverV1.sol";

/// @author DELV
/// @title LsETHConversions
/// @notice The conversion logic for the LsETH integration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library LsETHConversions {
    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _vaultSharesToken The vault shares asset.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IERC20 _vaultSharesToken,
        uint256 _shareAmount
    ) internal view returns (uint256) {
        return
            IRiverV1(address(_vaultSharesToken)).underlyingBalanceFromShares(
                _shareAmount
            );
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _vaultSharesToken The vault shares asset.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IERC20 _vaultSharesToken,
        uint256 _baseAmount
    ) internal view returns (uint256) {
        return
            IRiverV1(address(_vaultSharesToken)).sharesFromUnderlyingBalance(
                _baseAmount
            );
    }
}
