// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget1 } from "../../external/HyperdriveTarget1.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IRestakeManager } from "../../interfaces/IRenzo.sol";
import { EzETHBase } from "./EzETHBase.sol";

/// @author DELV
/// @title EzETHTarget1
/// @notice EzETHHyperdrive's target1 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EzETHTarget1 is HyperdriveTarget1, EzETHBase {
    /// @notice Initializes the target1 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _restakeManager The Renzo contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        IRestakeManager _restakeManager
    )
        HyperdriveTarget1(_config, __adminController)
        EzETHBase(_restakeManager)
    {}
}
