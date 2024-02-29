// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget4 } from "../../external/HyperdriveTarget4.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { ILido } from "../../interfaces/ILido.sol";
import { ezETHBase } from "./ezETHBase.sol";

/// @author DELV
/// @title ezETHTarget4
/// @notice ezETHHyperdrive's target4 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ezETHTarget4 is HyperdriveTarget4, ezETHBase {
    /// @notice Initializes the target4 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _lido The Lido contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        ILido _lido
    ) HyperdriveTarget4(_config) ezETHBase(_lido) {}
}
