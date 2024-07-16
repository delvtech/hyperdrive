// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

interface IEverlongPositions {
    struct Position {
        /// @dev Checkpoint time when the position matures.
        uint128 maturityTime;
        /// @dev Quantity of bonds in the position.
        uint128 bondAmount;
    }

    /// @notice Emitted when a new position is added.
    event PositionAdded(
        uint128 indexed maturityTime,
        uint128 bondAmount,
        uint256 index
    );

    /// @notice Emitted when an existing position's `bondAmount` is modified.
    event PositionUpdated(
        uint128 indexed maturityTime,
        uint128 newBondAmount,
        uint256 index
    );

    /// @notice Emitted when Everlong positions are rebalanced.
    event Rebalanced();

    /// @notice Gets the number of positions managed by the Everlong instance.
    /// @return The number of positions.
    function getNumberOfPositions() external view returns (uint256);

    /// @notice Gets the position at an index.
    ///         Position `maturityTime` increases with each index.
    /// @param _index The index of the position.
    /// @return The position.
    function getPositionAtIndex(
        uint256 _index
    ) external view returns (Position memory);

    /// @notice Rebalances positions managed by the Everlong instance if needed.
    function rebalance() external;
}
