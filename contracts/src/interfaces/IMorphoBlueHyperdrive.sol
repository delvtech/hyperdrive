// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { Id, IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { IHyperdrive } from "./IHyperdrive.sol";

interface IMorphoBlueHyperdrive is IHyperdrive {
    struct MorphoBlueParams {
        IMorpho morpho;
        address collateralToken;
        address oracle;
        address irm;
        uint256 lltv;
    }

    /// @notice Gets the vault used as this pool's yield source.
    /// @return The compatible yield source.
    function vault() external view returns (address);

    /// @notice Returns the collateral token for this Morpho Blue market.
    /// @return The collateral token for this Morpho Blue market.
    function collateralToken() external view returns (address);

    /// @notice Returns the oracle for this Morpho Blue market.
    /// @return The oracle for this Morpho Blue market.
    function oracle() external view returns (address);

    /// @notice Returns the interest rate model for this Morpho Blue market.
    /// @return The interest rate model for this Morpho Blue market.
    function irm() external view returns (address);

    /// @notice Returns the liquidation loan to value ratio for this Morpho Blue
    ///         market.
    /// @return The liquiditation loan to value ratio for this Morpho Blue market.
    function lltv() external view returns (uint256);

    /// @notice Returns the Morpho Blue ID for this market.
    /// @return The Morpho Blue ID.
    function id() external view returns (Id);
}
