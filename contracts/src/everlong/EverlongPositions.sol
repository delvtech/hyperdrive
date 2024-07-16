// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IEverlongPositions } from "contracts/src/interfaces/IEverlongPositions.sol";
import { DoubleEndedQueue } from "openzeppelin/utils/structs/DoubleEndedQueue.sol";

/// @author DELV
/// @title Everlong
/// @notice Accounting for the Hyperdrive bond positions managed by Everlong.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EverlongPositions is IEverlongPositions {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    // TODO: Reassess using a more tailored data structure.
    DoubleEndedQueue.Bytes32Deque internal _positions;

    /// @inheritdoc IEverlongPositions
    function getNumberOfPositions() external view returns (uint256) {
        return _positions.length();
    }

    /// @inheritdoc IEverlongPositions
    function getPositionAtIndex(
        uint256 _index
    ) external view returns (Position memory) {
        Position memory position = abi.decode(
            abi.encodePacked(_positions.at(_index)),
            (Position)
        );
        return position;
    }

    /// @inheritdoc IEverlongPositions
    function rebalance() external pure {
        revert("TODO");
    }
}
