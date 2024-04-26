// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget1 } from "../../external/HyperdriveTarget1.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IMorpho, MarketParams } from "../../interfaces/IMorpho.sol";
import { MorphoBase } from "./MorphoBase.sol";

/// @author DELV
/// @title MorphoTarget1
/// @notice MorphoHyperdrive's target1 logic contract. This contract contains
///         several stateful functions that couldn't fit into the Hyperdrive
///         contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MorphoTarget1 is HyperdriveTarget1, MorphoBase {
    /// @notice Initializes the target1 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _morpho The Morpho contract.
    /// @param _marketParams The Morpho market information.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IMorpho _morpho,
        MarketParams memory _marketParams
    ) HyperdriveTarget1(_config) MorphoBase(_morpho, _marketParams) {}
}
