// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IChainlinkAggregatorV3 } from "./IChainlinkAggregatorV3.sol";
import { IHyperdrive } from "./IHyperdrive.sol";

interface IChainlinkHyperdrive is IHyperdrive {
    /// @notice Gets the Chainlink aggregator that provides the pool's vault
    ///         share price.
    /// @return The chainlink aggregator.
    function aggregator() external view returns (IChainlinkAggregatorV3);
}
