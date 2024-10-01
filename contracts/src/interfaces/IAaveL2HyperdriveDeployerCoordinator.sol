// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IL2Pool } from "./IAave.sol";
import { IERC20 } from "./IERC20.sol";
import { IHyperdriveDeployerCoordinator } from "./IHyperdriveDeployerCoordinator.sol";

interface IAaveL2HyperdriveDeployerCoordinator is
    IHyperdriveDeployerCoordinator
{
    /// @notice Convert an amount of vault shares to an amount of base.
    /// @param _baseToken The base token.
    /// @param _vault The AaveL2 vault.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IERC20 _baseToken,
        IL2Pool _vault,
        uint256 _shareAmount
    ) external view returns (uint256);

    /// @notice Convert an amount of base to an amount of vault shares.
    /// @param _baseToken The base token.
    /// @param _vault The AaveL2 vault.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IERC20 _baseToken,
        IL2Pool _vault,
        uint256 _baseAmount
    ) external view returns (uint256);
}
