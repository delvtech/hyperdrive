// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget4 } from "../../external/HyperdriveTarget4.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { RETHBase } from "./RETHBase.sol";

/// @author DELV
/// @title RETHTarget4
/// @notice RETHHyperdrive's target4 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract RETHTarget4 is HyperdriveTarget4, RETHBase {
    /// @notice Initializes the target4 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController
    ) HyperdriveTarget4(_config, __adminController) {}
}
