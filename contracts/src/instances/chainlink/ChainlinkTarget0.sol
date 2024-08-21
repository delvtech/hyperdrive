// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IChainlinkAggregatorV3 } from "../../interfaces/IChainlinkAggregatorV3.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { CHAINLINK_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { ChainlinkBase } from "./ChainlinkBase.sol";

/// @author DELV
/// @title ChainlinkTarget0
/// @notice ChainlinkHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ChainlinkTarget0 is HyperdriveTarget0, ChainlinkBase {
    /// @notice Initializes the target0 contract.
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
        HyperdriveTarget0(_config, __adminController)
        ChainlinkBase(__aggregator, __decimals)
    {}

    /// Getters ///

    /// @notice Returns the instance's kind.
    /// @return The instance's kind.
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(CHAINLINK_HYPERDRIVE_KIND));
    }

    /// @notice Returns the instance's Chainlink aggregator. This is the
    ///         Chainlink contract that provides the vault share price.
    /// @return aggregator The Chainlink aggregator.
    function aggregator() external view returns (IChainlinkAggregatorV3) {
        _revert(abi.encode(_aggregator));
    }

    /// @notice Returns the MultiToken's decimals.
    /// @return The MultiToken's decimals.
    function decimals() external view override returns (uint8) {
        _revert(abi.encode(_decimals));
    }
}
