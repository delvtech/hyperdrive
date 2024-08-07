// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20 } from "./IERC20.sol";
import { IHyperdriveCheckpointSubrewarder } from "../interfaces/IHyperdriveCheckpointSubrewarder.sol";

interface IHyperdriveCheckpointRewarder {
    /// @notice Emitted when the admin is transferred.
    event AdminUpdated(address indexed admin);

    /// @notice Emitted when the subrewarder is updated.
    event SubrewarderUpdated(
        IHyperdriveCheckpointSubrewarder indexed subrewarder
    );

    /// @notice Emitted when a checkpoint reward is claimed.
    event CheckpointRewardClaimed(
        address indexed instance,
        address indexed claimant,
        bool indexed isTrader,
        uint256 checkpointTime,
        IERC20 rewardToken,
        uint256 rewardAmount
    );

    /// @notice Thrown when caller is not governance.
    error Unauthorized();

    /// @notice Allows the admin to transfer the admin role.
    /// @param _admin The new admin address.
    function updateAdmin(address _admin) external;

    /// @notice Allows the admin to update the subrewarder.
    /// @param _subrewarder The rewarder that will be delegated to.
    function updateSubrewarder(
        IHyperdriveCheckpointSubrewarder _subrewarder
    ) external;

    /// @notice Claims a checkpoint reward.
    /// @param _claimant The address that is claiming the checkpoint reward.
    /// @param _checkpointTime The time of the checkpoint that was minted.
    /// @param _isTrader A boolean indicating whether or not the checkpoint was
    ///        minted by a trader or by someone calling checkpoint directly.
    function claimCheckpointReward(
        address _claimant,
        uint256 _checkpointTime,
        bool _isTrader
    ) external;

    /// @notice Gets the rewarder's name.
    /// @return The rewarder's name.
    function name() external view returns (string memory);

    /// @notice Gets the rewarder's kind.
    /// @return The rewarder's kind.
    function kind() external pure returns (string memory);

    /// @notice Gets the rewarder's version.
    /// @return The rewarder's version.
    function version() external pure returns (string memory);

    /// @notice Returns the admin address that updates the rewarder's
    ///         configuration.
    /// @return The rewarder's admin address.
    function admin() external view returns (address);

    /// @notice Returns the subrewarder address that processes checkpoint
    ///         rewards.
    /// @return The rewarder's subrewarder address.
    function subrewarder()
        external
        view
        returns (IHyperdriveCheckpointSubrewarder);
}
