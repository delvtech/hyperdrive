// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { HyperdriveTarget1 } from "../../external/HyperdriveTarget1.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IMorphoBlueHyperdrive } from "../../interfaces/IMorphoBlueHyperdrive.sol";
import { MorphoBlueBase } from "./MorphoBlueBase.sol";

/// @author DELV
/// @title MorphoBlueTarget1
/// @notice MorphoBlueHyperdrive's target1 logic contract. This contract contains
///         several stateful functions that couldn't fit into the Hyperdrive
///         contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MorphoBlueTarget1 is HyperdriveTarget1, MorphoBlueBase {
    /// @notice Initializes the target1 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _params The Morpho Blue params.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IMorphoBlueHyperdrive.MorphoBlueParams memory _params
    ) HyperdriveTarget1(_config) MorphoBlueBase(_params) {}
}