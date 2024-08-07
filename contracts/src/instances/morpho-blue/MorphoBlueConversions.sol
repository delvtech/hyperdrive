// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IMorpho, MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";
import { SharesMathLib } from "morpho-blue/src/libraries/SharesMathLib.sol";
import { MorphoBalancesLib } from "morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { FixedPointMath } from "../../libraries/FixedPointMath.sol";

/// @author DELV
/// @title MorphoBlueConversions
/// @notice The conversion logic for the Morpho Blue integration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library MorphoBlueConversions {
    using FixedPointMath for uint256;
    using MorphoBalancesLib for IMorpho;
    using SharesMathLib for uint256;

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _vault The Morpho Blue contract.
    /// @param _baseToken The base token underlying the Morpho Blue vault.
    /// @param _collateralToken The collateral token for this Morpho Blue market.
    /// @param _oracle The oracle for this Morpho Blue market.
    /// @param _irm The IRM for this Morpho Blue market.
    /// @param _lltv The LLTV for this Morpho Blue market.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IMorpho _vault,
        IERC20 _baseToken,
        address _collateralToken,
        address _oracle,
        address _irm,
        uint256 _lltv,
        uint256 _shareAmount
    ) external view returns (uint256) {
        // Get the total supply assets and shares after interest accrues.
        (
            uint256 totalSupplyAssets,
            uint256 totalSupplyShares
        ) = getExpectedSupplyBalances(
                _vault,
                _baseToken,
                _collateralToken,
                _oracle,
                _irm,
                _lltv
            );

        return _shareAmount.toAssetsDown(totalSupplyAssets, totalSupplyShares);
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _vault The Morpho Blue vault.
    /// @param _baseToken The base token underlying the Morpho Blue vault.
    /// @param _collateralToken The collateral token for this Morpho Blue market.
    /// @param _oracle The oracle for this Morpho Blue market.
    /// @param _irm The IRM for this Morpho Blue market.
    /// @param _lltv The LLTV for this Morpho Blue market.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IMorpho _vault,
        IERC20 _baseToken,
        address _collateralToken,
        address _oracle,
        address _irm,
        uint256 _lltv,
        uint256 _baseAmount
    ) external view returns (uint256) {
        // Get the total supply assets and shares after interest accrues.
        (
            uint256 totalSupplyAssets,
            uint256 totalSupplyShares
        ) = getExpectedSupplyBalances(
                _vault,
                _baseToken,
                _collateralToken,
                _oracle,
                _irm,
                _lltv
            );

        return _baseAmount.toSharesDown(totalSupplyAssets, totalSupplyShares);
    }

    /// @dev Gets the Morpho Blue supply balances after accruing interest.
    /// @param _vault The Morpho Blue vault.
    /// @param _baseToken The base token underlying the Morpho Blue vault.
    /// @param _collateralToken The collateral token for this Morpho Blue market.
    /// @param _oracle The oracle for this Morpho Blue market.
    /// @param _irm The IRM for this Morpho Blue market.
    /// @param _lltv The LLTV for this Morpho Blue market.
    /// @return totalSupplyAssets The total amount of assets after interest.
    /// @return totalSupplyShares The total amount of shares after interest.
    function getExpectedSupplyBalances(
        IMorpho _vault,
        IERC20 _baseToken,
        address _collateralToken,
        address _oracle,
        address _irm,
        uint256 _lltv
    )
        internal
        view
        returns (uint256 totalSupplyAssets, uint256 totalSupplyShares)
    {
        (totalSupplyAssets, totalSupplyShares, , ) = _vault
            .expectedMarketBalances(
                MarketParams({
                    loanToken: address(_baseToken),
                    collateralToken: _collateralToken,
                    oracle: _oracle,
                    irm: _irm,
                    lltv: _lltv
                })
            );
        return (totalSupplyAssets, totalSupplyShares);
    }
}
