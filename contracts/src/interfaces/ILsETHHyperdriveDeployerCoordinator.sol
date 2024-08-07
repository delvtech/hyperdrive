// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20 } from "./IERC20.sol";
import { IHyperdriveDeployerCoordinator } from "./IHyperdriveDeployerCoordinator.sol";

interface ILsETHHyperdriveDeployerCoordinator is
    IHyperdriveDeployerCoordinator
{
    /// @notice Convert an amount of vault shares to an amount of base.
    /// @param _vaultSharesToken The vault shares asset.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IERC20 _vaultSharesToken,
        uint256 _shareAmount
    ) external view returns (uint256);

    /// @notice Convert an amount of base to an amount of vault shares.
    /// @param _vaultSharesToken The vault shares asset.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IERC20 _vaultSharesToken,
        uint256 _baseAmount
    ) external view returns (uint256);
}
