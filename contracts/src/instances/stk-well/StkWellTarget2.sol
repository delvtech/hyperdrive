// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget2 } from "../../external/HyperdriveTarget2.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { StkWellBase } from "./StkWellBase.sol";

/// @author DELV
/// @title StkWellTarget2
/// @notice StkWellHyperdrive's target2 logic contract. This contract contains
///         several stateful functions that couldn't fit into the Hyperdrive
///         contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StkWellTarget2 is HyperdriveTarget2, StkWellBase {
    /// @notice Initializes the target2 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController
    ) HyperdriveTarget2(_config, __adminController) {}
}
