// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget5 } from "../../external/HyperdriveTarget5.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { LsETHBase } from "./LsETHBase.sol";

/// @author DELV
/// @title LsETHTarget5
/// @notice LsETHHyperdrive's target5 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract LsETHTarget5 is HyperdriveTarget5, LsETHBase {
    /// @notice Initializes the target5 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveTarget5(_config) {}
}
