// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget2 } from "../../external/HyperdriveTarget2.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IRocketStorage } from "../../interfaces/IRocketStorage.sol";
import { RETHBase } from "./RETHBase.sol";

/// @author DELV
/// @title RETHTarget2
/// @notice RETHHyperdrive's target2 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract RETHTarget2 is HyperdriveTarget2, RETHBase {
    /// @notice Initializes the target2 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __rocketStorage The Rocket Pool storage contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IRocketStorage __rocketStorage
    ) HyperdriveTarget2(_config) RETHBase(__rocketStorage) {}
}
