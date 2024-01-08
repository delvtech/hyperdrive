// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveTarget2 } from "../../external/HyperdriveTarget2.sol";
import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { ERC4626Base } from "./ERC4626Base.sol";

/// @author DELV
/// @title ERC4626Target2
/// @notice ERC4626Hyperdrive's target 2 logic contract. This contract contains
///         several stateful functions that couldn't fit into the Hyperdrive
///         contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Target2 is HyperdriveTarget2, ERC4626Base {
    /// @notice Initializes the target2 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __pool The ERC4626 pool.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IERC4626 __pool
    ) HyperdriveTarget2(_config) ERC4626Base(__pool) {}
}
