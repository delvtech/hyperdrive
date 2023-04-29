// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { HyperdriveBase} from "./HyperdriveBase.sol";
import { Errors } from "./libraries/Errors.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";

/// @author DELV
/// @title HyperdriveTWAP
/// @notice Adds an oracle which records data on an interval and then loads the
///         average price between intervals.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveTWAP is HyperdriveBase {
    using FixedPointMath for *;

    /// @notice Records data into a time weighted sum oracle entry. This function only writes to the oracle
    ///         if some amount of time has passed since the previous update.
    /// @param price This is the data to be recorded into the oracle. Warn - the data should be able to fit
    ///              into 2^224 after being summed and so should be relatively small.
    function recordPrice(uint256 price) internal {
        // If there's no need to update we return
        if (uint256(lastTimestamp) + updateGap < block.timestamp) {
            return;
        }

        // To do a cumulative sum we load the previous sum
        uint256 head = uint256(head);
        uint256 toRead = head == 0 ? buffer.length - 1 : head - 1;
        // Load from storage
        uint256 previousTime = uint256(buffer[toRead].timestamp);
        uint256 previousSum = uint256(buffer[toRead].data);

        // Calculate sum
        uint256 delta = block.timestamp - previousTime;
        // NOTE - We do not expect this should ever overflow under normal conditions
        //        but if it would we would prefer that the oracle does not lock trade closes
        unchecked {
            uint256 sum = price * delta + previousSum;
        }

        // If we are updating first we calculate the index to update
        uint256 toUpdate = (uint256(head) + 1) % buffer.length;
        // Now we update the slot with this data
        buffer[toUpdate] = OracleData(uint32(block.timestamp), uint224(sum));
        head = uint128(toUpdate);
        lastTimestamp = uint128(block.timestamp);
    }

    /// @notice Returns the average price between the last recorded timestamp looking a user determined
    ///         time into the past
    /// @param period The gap in our time sample.
    /// @return The average price in that time
    function query(uint256 period) external view returns (uint256) {
        OracleData memory currentData = buffer[head];
        uint256 targetTime = uint256(lastTimestamp) - period;
        uint256 head = uint256(head);
        // Get the last index
        uint256 lastIndex = (head + 1) % buffer.length;

        // We search for the greatest timestamp before the last, note this is not
        // an efficient search as we expect the buffer to be small.
        uint256 currentIndex = head == 0 ? buffer.length - 1 : head - 1;
        OracleData memory oldData = OracleData(0, 0);
        while (lastIndex != currentIndex) {
            // If the timestamp of the current index has older data than the target
            // this is the newest data which is older than the target so we break
            if (uint256(buffer[currentIndex].timestamp) < targetTime) {
                oldData = buffer[currentIndex];
                break;
            }
            currentIndex = currentIndex == 0 ? buffer.length : currentIndex - 1;
        }

        if (oldData.timestamp == 0) revert Errors.QueryOutOfRange();

        // To get twap in period we take the increase in the sum then divide by
        // the amount of time passed
        uint256 deltaSum = uint256(currentData.data) - uint256(oldData.data);
        uint256 deltaTime = uint256(currentData.timestamp) -
            uint256(oldData.timestamp);
        return (deltaSum.divDown(deltaTime));
    }
}
