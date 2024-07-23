// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IChainlinkAggregatorV3 } from "../../interfaces/IChainlinkAggregatorV3.sol";
import { FixedPointMath } from "../../libraries/FixedPointMath.sol";
import { SafeCast } from "../../libraries/SafeCast.sol";

// FIXME: This is the contract that will have to deal with things like uptime
//        and when the answer is from.
//
// FIXME: How will we handle oracle outages?
//
// FIXME: How will we handle deprecation or data feed shutdown?
//
/// @author DELV
/// @title ChainlinkConversions
/// @notice The conversion logic for the Chainlink integration.
/// @dev FIXME: It would be good to explain the limitations of these conversions.
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

    // FIXME: Natspec
    //
    // FIXME: Handle uptime if necessary.
    function getVaultSharePrice(
        IChainlinkAggregatorV3 _aggregator
    ) internal view returns (uint256) {
        // FIXME: At a bare minimum, we should use answer and updatedAt. We
        //        should also consider using `answeredInRound` to provide some
        //        additional security.
        (, int256 answer, , uint256 updatedAt, ) = _aggregator
            .latestRoundData();
        return answer.toUint256();
    }
}
