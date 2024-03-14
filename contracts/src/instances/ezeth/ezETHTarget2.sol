// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC20 } from "../../interfaces/IERC20.sol";
import { HyperdriveTarget2 } from "../../external/HyperdriveTarget2.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IRestakeManager } from "../../interfaces/IRestakeManager.sol";
import { EzETHBase } from "./EzETHBase.sol";

/// @author DELV
/// @title EzETHTarget2
/// @notice EzETHHyperdrive's target2 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EzETHTarget2 is HyperdriveTarget2, EzETHBase {
    /// @notice Initializes the target2 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _restakeManager The Renzo contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IRestakeManager _restakeManager
    ) HyperdriveTarget2(_config) EzETHBase(_restakeManager) {}
}
