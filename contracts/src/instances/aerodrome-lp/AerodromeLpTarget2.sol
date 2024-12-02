// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { IGauge } from "aerodrome/interfaces/IGauge.sol";
import { HyperdriveTarget2 } from "../../external/HyperdriveTarget2.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { AerodromeLpBase } from "./AerodromeLpBase.sol";

/// @author DELV
/// @title AerodromeLpTarget2
/// @notice AerodromeLpHyperdrive's target2 logic contract. This contract contains
///         several stateful functions that couldn't fit into the Hyperdrive
///         contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract AerodromeLpTarget2 is HyperdriveTarget2, AerodromeLpBase {
    /// @notice Initializes the target2 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _gauge The Aerodrome Gauge contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        IGauge _gauge
    ) HyperdriveTarget2(_config, __adminController) AerodromeLpBase(_gauge) {}
}
