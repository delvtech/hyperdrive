// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IChainlinkAggregatorV3 } from "../../interfaces/IChainlinkAggregatorV3.sol";
import { FixedPointMath } from "../../libraries/FixedPointMath.sol";
import { SafeCast } from "../../libraries/SafeCast.sol";

/// @author DELV
/// @title ChainlinkConversions
/// @notice The conversion logic for the Chainlink integration.
/// @dev This conversion library pulls the vault share price from a Chainlink
///      aggregator. It's possible for Chainlink aggregators to have downtime or
///      to be deprecated entirely. Our approach to this problem is to always
///      use the latest round data (regardless of how current it is) since
///      reverting will compromise the protocol's liveness and will prevent
///      users from closing their existing positions. These pools should be
///      monitored to ensure that the underlying oracle continues to be
///      maintained, and the pool should be paused if the oracle has significant
///      downtime or is deprecated.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library ChainlinkConversions {
    using FixedPointMath for uint256;
    using SafeCast for int256;

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _aggregator The Chainlink aggregator that provides the vault
    ///        share price.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IChainlinkAggregatorV3 _aggregator,
        uint256 _shareAmount
    ) internal view returns (uint256) {
        return _shareAmount.mulDown(getVaultSharePrice(_aggregator));
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _aggregator The Chainlink aggregator that provides the vault
    ///        share price.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IChainlinkAggregatorV3 _aggregator,
        uint256 _baseAmount
    ) internal view returns (uint256) {
        return _baseAmount.divDown(getVaultSharePrice(_aggregator));
    }

    /// @dev Gets the vault share price from the Chainlink aggregator. We don't
    ///      revert if the answer isn't current to avoid liveness problems with
    ///      checkpointing. Long periods of downtime will be handled by pausing
    ///      the pool.
    /// @param _aggregator The Chainlink aggregator that provides the vault
    ///        share price.
    /// @return The vault share price.
    function getVaultSharePrice(
        IChainlinkAggregatorV3 _aggregator
    ) internal view returns (uint256) {
        (, int256 answer, , , ) = _aggregator.latestRoundData();
        return answer.toUint256();
    }
}
