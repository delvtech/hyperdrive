// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IEverlongPositions } from "contracts/src/interfaces/IEverlongPositions.sol";
import { DoubleEndedQueue } from "openzeppelin/utils/structs/DoubleEndedQueue.sol";

contract EverlongPositions is IEverlongPositions {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    DoubleEndedQueue.Bytes32Deque internal _positions;

    /// @notice Gets the number of positions managed by the Everlong instance.
    /// @return The number of positions.
    function getNumberOfPositions() external view returns (uint256) {
        return _positions.length();
    }

    /// @notice Gets the position at an index.
    /// @param _index The index of the position.
    /// @return The position.
    function getPositionAtIndex(
        uint256 _index
    ) external view returns (Position memory) {
        Position memory position = abi.decode(
            abi.encodePacked(_positions.at(_index)),
            (Position)
        );
        return position;
    }

    /// @notice Rebalances positions managed by the Everlong instance if needed.
    function rebalance() external pure {
        revert("TODO");
    }
}
