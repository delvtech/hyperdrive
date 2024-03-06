// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget1 } from "../../external/HyperdriveTarget1.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { ILido } from "../../interfaces/ILido.sol";
import { StETHBase } from "./StETHBase.sol";

/// @author DELV
/// @title StETHTarget1
/// @notice StETHHyperdrive's target1 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StETHTarget1 is HyperdriveTarget1, StETHBase {
    /// @notice Initializes the target1 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __lido The Lido contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        ILido __lido
    ) HyperdriveTarget1(_config) StETHBase(__lido) {}
}
