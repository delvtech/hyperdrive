// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget5 } from "../../external/HyperdriveTarget5.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { RETHBase } from "./RETHBase.sol";

/// @author DELV
/// @title RETHTarget5
/// @notice RETHHyperdrive's target5 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract RETHTarget5 is HyperdriveTarget5, RETHBase {
    /// @notice Initializes the target4 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveTarget5(_config) {}
}
