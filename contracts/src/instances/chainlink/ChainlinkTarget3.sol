// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget3 } from "../../external/HyperdriveTarget3.sol";
import { IChainlinkAggregatorV3 } from "../../interfaces/IChainlinkAggregatorV3.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { ChainlinkBase } from "./ChainlinkBase.sol";

/// @author DELV
/// @title ChainlinkTarget3
/// @notice ChainlinkHyperdrive's target3 logic contract. This contract contains
///         several stateful functions that couldn't fit into the Hyperdrive
///         contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ChainlinkTarget3 is HyperdriveTarget3, ChainlinkBase {
    /// @notice Initializes the target3 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param __aggregator The Chainlink aggregator. This is the contract that
    ///        will return the answer.
    /// @param __decimals The decimals of this Hyperdrive instance's bonds and
    ///        LP tokens.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        IChainlinkAggregatorV3 __aggregator,
        uint8 __decimals
    )
        HyperdriveTarget3(_config, __adminController)
        ChainlinkBase(__aggregator, __decimals)
    {}
}
