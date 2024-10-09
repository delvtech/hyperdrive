// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget4 } from "../../external/HyperdriveTarget4.sol";
import { ICornSilo } from "../../interfaces/ICornSilo.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { CornBase } from "./CornBase.sol";

/// @author DELV
/// @title CornTarget4
/// @notice CornHyperdrive's target4 logic contract. This contract contains
///         several stateful functions that couldn't fit into the Hyperdrive
///         contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract CornTarget4 is HyperdriveTarget4, CornBase {
    /// @notice Initializes the target4 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param __cornSilo The Corn Silo contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        ICornSilo __cornSilo
    ) HyperdriveTarget4(_config, __adminController) CornBase(__cornSilo) {}
}
