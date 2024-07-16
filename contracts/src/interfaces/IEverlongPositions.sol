// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

interface IEverlongPositions {
    /// @dev Tracks the total amount of bonds managed by Everlong
    ///      with the same maturityTime.
    struct Position {
        /// @dev Checkpoint time when the position matures.
        uint128 maturityTime;
        /// @dev Quantity of bonds in the position.
        uint128 bondAmount;
    }

    /// @notice Emitted when a new position is added.
    /// TODO: Include wording for distinct maturity times if appropriate.
    /// TODO: Reconsider naming https://github.com/delvtech/hyperdrive/pull/1096#discussion_r1681337414
    event PositionAdded(
        uint128 indexed maturityTime,
        uint128 bondAmount,
        uint256 index
    );

    /// @notice Emitted when an existing position's `bondAmount` is modified.
    /// TODO: Reconsider naming https://github.com/delvtech/hyperdrive/pull/1096#discussion_r1681337414
    event PositionUpdated(
        uint128 indexed maturityTime,
        uint128 newBondAmount,
        uint256 index
    );

    /// @notice Emitted when Everlong's underlying portfolio is rebalanced..
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

    /// @notice Rebalances the Everlong bond portfolio if needed.
    function rebalance() external;
}
