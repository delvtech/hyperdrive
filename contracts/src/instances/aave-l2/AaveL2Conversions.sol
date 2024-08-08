// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IL2Pool } from "../../interfaces/IAave.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { FixedPointMath } from "../../libraries/FixedPointMath.sol";

/// @author DELV
/// @title AaveL2Conversions
/// @notice The conversion logic for the AaveL2 integration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library AaveL2Conversions {
    using FixedPointMath for uint256;

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _baseToken The base token underlying the AaveL2 vault.
    /// @param _vault The AaveL2 vault.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IERC20 _baseToken,
        IL2Pool _vault,
        uint256 _shareAmount
    ) internal view returns (uint256) {
        // AaveL2's AToken accounting calls shares "scaled tokens." We can convert
        // from scaled tokens to aTokens with the formula:
        //
        // aToken = scaledToken.rayMul(POOL.getReserveNormalizedIncome(_underlyingAsset))
        //
        // `rayMul` computes a 27 decimal fixed point multiplication and
        // `_underlyingAsset` is the base token address.
        //
        // NOTE: We use `mulDivDown` with 27 decimals of precision to compute
        // the calculation to ensure that we are always rounding down since
        // `rayDiv` will round up in some cases.
        return
            _shareAmount.mulDivDown(
                getReserveNormalizedIncome(_baseToken, _vault),
                1e27
            );
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseToken The base token underlying the AaveL2 vault.
    /// @param _vault The AaveL2 vault.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IERC20 _baseToken,
        IL2Pool _vault,
        uint256 _baseAmount
    ) internal view returns (uint256) {
        // AaveL2's AToken accounting calls shares "scaled tokens." We can convert
        // from aTokens to scaled tokens with the formula:
        //
        // scaledToken = aToken.rayDiv(
        //     POOL.getReserveNormalizedIncome(_underlyingAsset)
        // )
        //
        // `rayDiv` computes a 27 decimal fixed point division and
        // `_underlyingAsset` is the base token address.
        //
        // NOTE: We use `mulDivDown` with 27 decimals of precision to compute
        // the calculation to ensure that we are always rounding down since
        // `rayDiv` will round up in some cases.
        return
            _baseAmount.mulDivDown(
                1e27,
                getReserveNormalizedIncome(_baseToken, _vault)
            );
    }

    /// @dev Gets the AaveL2 vault's reserve normalized income. This helper is
    ///      used to reduce the code size.
    /// @param _baseToken The base token underlying the AaveL2 vault.
    /// @param _vault The AaveL2 vault.
    /// @return The AaveL2 vault's reserve normalized income.
    function getReserveNormalizedIncome(
        IERC20 _baseToken,
        IL2Pool _vault
    ) internal view returns (uint256) {
        return _vault.getReserveNormalizedIncome(address(_baseToken));
    }
}
