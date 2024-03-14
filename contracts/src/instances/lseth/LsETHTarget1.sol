// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget1 } from "../../external/HyperdriveTarget1.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IRiverV1 } from "../../interfaces/lseth/IRiverV1.sol";
import { LsETHBase } from "./LsETHBase.sol";

/// @author DELV
/// @title LsETHTarget1
/// @notice LsETHHyperdrive's target1 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract LsETHTarget1 is HyperdriveTarget1, LsETHBase {
    /// @notice Initializes the target1 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __river The Lido contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IRiverV1 __river
    ) HyperdriveTarget1(_config) LsETHBase(__river) {}
}
