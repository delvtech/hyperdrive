// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget3 } from "../../external/HyperdriveTarget3.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IMorphoBlueHyperdrive } from "../../interfaces/IMorphoBlueHyperdrive.sol";
import { MorphoBlueBase } from "./MorphoBlueBase.sol";

/// @author DELV
/// @title MorphoBlueTarget3
/// @notice MorphoBlueHyperdrive's target3 logic contract. This contract contains
///         several stateful functions that couldn't fit into the Hyperdrive
///         contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MorphoBlueTarget3 is HyperdriveTarget3, MorphoBlueBase {
    /// @notice Initializes the target3 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _params The Morpho Blue params.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        IMorphoBlueHyperdrive.MorphoBlueParams memory _params
    ) HyperdriveTarget3(_config, __adminController) MorphoBlueBase(_params) {}
}
