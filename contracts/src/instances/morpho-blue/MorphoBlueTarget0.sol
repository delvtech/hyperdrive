// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IMorphoBlueHyperdrive } from "../../interfaces/IMorphoBlueHyperdrive.sol";
import { MORPHO_BLUE_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { MorphoBlueBase } from "./MorphoBlueBase.sol";

/// @author DELV
/// @title MorphoBlueTarget0
/// @notice MorphoBlueHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MorphoBlueTarget0 is HyperdriveTarget0, MorphoBlueBase {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _params The Morpho Blue params.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IMorphoBlueHyperdrive.MorphoBlueParams memory _params
    ) HyperdriveTarget0(_config) MorphoBlueBase(_params) {}

    /// @notice Returns the instance's kind.
    /// @return The instance's kind.
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(MORPHO_BLUE_HYPERDRIVE_KIND));
    }

    /// @notice Returns the Morpho Blue contract.
    /// @return The Morpho Blue contract.
    function vault() external view returns (IMorpho) {
        _revert(abi.encode(_vault));
    }

    /// @notice Returns the collateral token for this Morpho Blue market.
    /// @return The collateral token for this Morpho Blue market.
    function collateralToken() external view returns (address) {
        _revert(abi.encode(_collateralToken));
    }

    /// @notice Returns the oracle for this Morpho Blue market.
    /// @return The oracle for this Morpho Blue market.
    function oracle() external view returns (address) {
        _revert(abi.encode(_oracle));
    }

    /// @notice Returns the IRM for this Morpho Blue market.
    /// @return The IRM for this Morpho Blue market.
    function irm() external view returns (address) {
        _revert(abi.encode(_irm));
    }

    /// @notice Returns the LLTV for this Morpho Blue market.
    /// @return The LLTV for this Morpho Blue market.
    function lltv() external view returns (uint256) {
        _revert(abi.encode(_lltv));
    }
}
