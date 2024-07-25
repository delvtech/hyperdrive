// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IChainlinkAggregatorV3 } from "../../interfaces/IChainlinkAggregatorV3.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
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
    /// @param __aggregator The Chainlink aggregator. This is the contract that
    ///        will return the answer.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IChainlinkAggregatorV3 __aggregator
    ) HyperdriveTarget0(_config) ChainlinkBase(__aggregator) {}

    /// @notice Returns the instance's kind.
    /// @return The instance's kind.
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(CHAINLINK_HYPERDRIVE_KIND));
    }

    /// @notice Returns the instance's Chainlink aggregator. This is the
    ///         Chainlink contract that provides the vault share price.
    /// @return aggregator The Chainlink aggregator.
    function aggregator() external view returns (IChainlinkAggregatorV3) {
        return _aggregator;
    }

    // FIXME: Should we add decimals here?
}
