// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "../../interfaces/IERC20.sol";
import { IRestakeManager, IRenzoOracle } from "../../interfaces/IRenzo.sol";

/// @author DELV
/// @title EzETHConversions
/// @notice The conversion logic for the EzETH integration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library EzETHConversions {
    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _renzoOracle The RenzoOracle contract.
    /// @param _restakeManager The Renzo entrypoint contract.
    /// @param _vaultSharesToken The vault shares asset.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IRenzoOracle _renzoOracle,
        IRestakeManager _restakeManager,
        IERC20 _vaultSharesToken,
        uint256 _shareAmount
    ) internal view returns (uint256) {
        // Get the total TVL priced in ETH from restakeManager
        (, , uint256 totalTVL) = _restakeManager.calculateTVLs();

        // Get the total supply of the ezETH token
        uint256 totalSupply = _vaultSharesToken.totalSupply();

        return
            _renzoOracle.calculateRedeemAmount(
                _shareAmount,
                totalSupply,
                totalTVL
            );
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _renzoOracle The RenzoOracle contract.
    /// @param _restakeManager The Renzo entrypoint contract.
    /// @param _vaultSharesToken The vault shares asset.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IRenzoOracle _renzoOracle,
        IRestakeManager _restakeManager,
        IERC20 _vaultSharesToken,
        uint256 _baseAmount
    ) internal view returns (uint256) {
        // Get the total TVL priced in ETH from restakeManager
        (, , uint256 totalTVL) = _restakeManager.calculateTVLs();

        // Get the total supply of the ezETH token
        uint256 totalSupply = _vaultSharesToken.totalSupply();

        return
            _renzoOracle.calculateMintAmount(
                totalTVL,
                _baseAmount,
                totalSupply
            );
    }
}
