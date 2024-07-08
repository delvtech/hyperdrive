// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { AaveBase } from "./AaveBase.sol";

/// @author DELV
/// @title AaveTarget0
/// @notice AaveHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract AaveTarget0 is HyperdriveTarget0, AaveBase {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveTarget0(_config) {}
}
