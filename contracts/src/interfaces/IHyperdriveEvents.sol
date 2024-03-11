// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IMultiTokenEvents } from "./IMultiTokenEvents.sol";

interface IHyperdriveEvents is IMultiTokenEvents {
    /// @notice Emitted when the Hyperdrive pool is initialized.
    event Initialize(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 vaultShareAmount,
        bool asBase,
        uint256 apr
    );

    /// @notice Emitted when an LP adds liquidity to the Hyperdrive pool.
    event AddLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 vaultShareAmount,
        bool asBase,
        uint256 lpSharePrice
    );

    /// @notice Emitted when an LP removes liquidity from the Hyperdrive pool.
    event RemoveLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 vaultShareAmount,
        bool asBase,
        uint256 withdrawalShareAmount,
        uint256 lpSharePrice
    );

    /// @notice Emitted when an LP redeems withdrawal shares.
    event RedeemWithdrawalShares(
        address indexed provider,
        uint256 withdrawalShareAmount,
        uint256 baseAmount,
        uint256 vaultShareAmount,
        bool asBase
    );

    /// @notice Emitted when a long position is opened.
    event OpenLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 vaultShareAmount,
        bool asBase,
        uint256 bondAmount
    );

    /// @notice Emitted when a short position is opened.
    event OpenShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 vaultShareAmount,
        bool asBase,
        uint256 baseProceeds,
        uint256 bondAmount
    );

    /// @notice Emitted when a long position is closed.
    event CloseLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 vaultShareAmount,
        bool asBase,
        uint256 bondAmount
    );

    /// @notice Emitted when a short position is closed.
    event CloseShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 vaultShareAmount,
        bool asBase,
        uint256 bondAmount
    );

    /// @notice Emitted when a checkpoint is created.
    event CreateCheckpoint(
        uint256 indexed checkpointTime,
        uint256 vaultSharePrice,
        uint256 maturedShorts,
        uint256 maturedLongs,
        uint256 lpSharePrice
    );

    /// @notice Emitted when governance fees are collected.
    event CollectGovernanceFee(address indexed collector, uint256 fees);

    /// @notice Emitted when the fee collector address is updated.
    event FeeCollectorUpdated(address indexed newFeeCollector);

    /// @notice Emitted when the sweep collector address is updated.
    event SweepCollectorUpdated(address indexed newSweepCollector);

    /// @notice Emitted when the governance address is updated.
    event GovernanceUpdated(address indexed newGovernance);

    /// @notice Emitted when a pauser is updated.
    event PauserUpdated(address indexed newPauser, bool status);

    /// @notice Emitted when the pause status is updated.
    event PauseStatusUpdated(bool isPaused);

    /// @notice Emitted when tokens are swept.
    event Sweep(address indexed collector, address indexed target);
}
