// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget3 } from "../../external/HyperdriveTarget3.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IRestakeManager } from "../../interfaces/IRestakeManager.sol";
import { ezETHBase } from "./ezETHBase.sol";

/// @author DELV
/// @title ezETHTarget3
/// @notice ezETHHyperdrive's target3 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ezETHTarget3 is HyperdriveTarget3, ezETHBase {
    /// @notice Initializes the target3 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _restakeManager The Renzo contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IRestakeManager _restakeManager
    ) HyperdriveTarget3(_config) ezETHBase(_restakeManager) {}
}
