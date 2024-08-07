// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget2 } from "../../external/HyperdriveTarget2.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { LsETHBase } from "./LsETHBase.sol";

/// @author DELV
/// @title LsETHTarget2
/// @notice LsETHHyperdrive's target2 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract LsETHTarget2 is HyperdriveTarget2, LsETHBase {
    /// @notice Initializes the target2 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveTarget2(_config) {}
}
