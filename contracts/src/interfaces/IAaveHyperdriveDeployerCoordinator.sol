// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IPool } from "aave/interfaces/IPool.sol";
import { IERC20 } from "./IERC20.sol";
import { IHyperdriveDeployerCoordinator } from "./IHyperdriveDeployerCoordinator.sol";

interface IAaveHyperdriveDeployerCoordinator is IHyperdriveDeployerCoordinator {
    /// @notice Convert an amount of vault shares to an amount of base.
    /// @param _baseToken The base token.
    /// @param _vault The Aave vault.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IERC20 _baseToken,
        IPool _vault,
        uint256 _shareAmount
    ) external view returns (uint256);

    /// @notice Convert an amount of base to an amount of vault shares.
    /// @param _baseToken The base token.
    /// @param _vault The Aave vault.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IERC20 _baseToken,
        IPool _vault,
        uint256 _baseAmount
    ) external view returns (uint256);
}
