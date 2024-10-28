// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IMToken } from "../../interfaces/IMoonwell.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { FixedPointMath } from "../../libraries/FixedPointMath.sol";

/// @author DELV
/// @title MoonwellConversions
/// @notice The conversion logic for the  Moonwell Hyperdrive integration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library MoonwellConversions {
    using FixedPointMath for uint256;

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IMToken _vaultSharesToken,
        uint256 _shareAmount
    ) external view returns (uint256) {
        // revert IHyperdrive.UnsupportedToken();
        return _shareAmount.mulDown(_vaultSharesToken.exchangeRateStored());
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IMToken _vaultSharesToken,
        uint256 _baseAmount
    ) external view returns (uint256) {
        // revert IHyperdrive.UnsupportedToken();
        return _baseAmount.divDown(_vaultSharesToken.exchangeRateStored());
    }
}