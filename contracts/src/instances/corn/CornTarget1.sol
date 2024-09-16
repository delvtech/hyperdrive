// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget1 } from "../../external/HyperdriveTarget1.sol";
import { ICornSilo } from "../../interfaces/ICornSilo.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { CornBase } from "./CornBase.sol";

/// @author DELV
/// @title CornTarget1
/// @notice CornHyperdrive's target1 logic contract. This contract contains
///         several stateful functions that couldn't fit into the Hyperdrive
///         contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract CornTarget1 is HyperdriveTarget1, CornBase {
    /// @notice Initializes the target1 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param __cornSilo The Corn Silo contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        ICornSilo __cornSilo
    ) HyperdriveTarget1(_config, __adminController) CornBase(__cornSilo) {}
}
