// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveBase } from "./HyperdriveBase.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { SafeCast } from "./libraries/SafeCast.sol";

/// @author DELV
/// @title HyperdriveTWAP
/// @notice Adds an oracle which records data on an interval and then loads the
///         average price between intervals.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveTWAP is HyperdriveBase {
    using FixedPointMath for uint256;
    using SafeCast for uint256;

    /// @notice Records data into a time weighted sum oracle entry. This function only writes to the oracle
    ///         if some amount of time has passed since the previous update.
    /// @param price This is the data to be recorded into the oracle. Warn - the data should be able to fit
    ///              into 2^224 after being summed and so should be relatively small.
    function recordPrice(uint256 price) internal {
        uint256 lastTimestamp = uint256(_oracle.lastTimestamp);
        uint256 head = uint256(_oracle.head);

        // If there's no need to update we return
        if (lastTimestamp + _updateGap > block.timestamp) {
            return;
        }

        // Load the current data from storage
        uint256 previousTime = uint256(_oracle.lastTimestamp);
        uint256 previousSum = uint256(_buffer[head].data);

        // Calculate sum
        uint256 delta = block.timestamp - previousTime;
        // NOTE - We do not expect this should ever overflow under normal conditions
        //        but if it would we would prefer that the oracle does not lock trade closes
        uint256 sum;
        unchecked {
            sum = price * delta + previousSum;
        }

        // If we are updating first we calculate the index to update
        uint256 toUpdate = (uint256(head) + 1) % _buffer.length;
        // Now we update the slot with this data
        _buffer[toUpdate] = OracleData(
            uint32(block.timestamp),
            sum.toUint224()
        );
        _oracle = IHyperdrive.OracleState(
            toUpdate.toUint128(),
            uint128(block.timestamp)
        );
    }
}
