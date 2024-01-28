// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget1 } from "../../external/HyperdriveTarget1.sol";
import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { ERC4626Base } from "./ERC4626Base.sol";

/// @author DELV
/// @title ERC4626Target1
/// @notice ERC4626Hyperdrive's target1 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Target1 is HyperdriveTarget1, ERC4626Base {
    /// @notice Initializes the target1 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __vault The ERC4626 compatible vault.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IERC4626 __vault
    ) HyperdriveTarget1(_config) ERC4626Base(__vault) {}
}
