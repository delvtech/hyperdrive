// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget3 } from "../../external/HyperdriveTarget3.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IRiverV1 } from "../../interfaces/lseth/IRiverV1.sol";
import { LsETHBase } from "./LsETHBase.sol";

/// @author DELV
/// @title LsETHTarget3
/// @notice LsETHHyperdrive's target3 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract LsETHTarget3 is HyperdriveTarget3, LsETHBase {
    /// @notice Initializes the target3 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __river The lsETH contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IRiverV1 __river
    ) HyperdriveTarget3(_config) LsETHBase(__river) {}
}
