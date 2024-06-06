// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC20 } from "./IERC20.sol";
import { IHyperdriveRegistry } from "../interfaces/IHyperdriveRegistry.sol";

interface IHyperdriveCheckpointSubrewarder {
    /// @notice Emitted when the admin is transferred.
    event AdminUpdated(address indexed admin);

    /// @notice Emitted when the registry is updated.
    event RegistryUpdated(IHyperdriveRegistry indexed registry);

    /// @notice Emitted when the reward token is updated.
    event RewardTokenUpdated(IERC20 indexed rewardToken);

    /// @notice Emitted when the source is updated.
    event SourceUpdated(address indexed source);

    /// @notice Emitted when the trader reward amount is updated.
    event TraderRewardAmountUpdated(uint256 indexed traderRewardAmount);

    /// @notice Emitted when the minter reward amount is updated.
    event MinterRewardAmountUpdated(uint256 indexed minterRewardAmount);

    /// @notice Thrown when caller is not governance.
    error Unauthorized();

    /// @notice Claims a checkpoint reward.
    /// @param _instance The instance that submitted the claim.
    /// @param _claimant The address that is claiming the checkpoint reward.
    /// @param _checkpointTime The time of the checkpoint that was minted.
    /// @param _isTrader A boolean indicating whether or not the checkpoint was
    ///        minted by a trader or by someone calling checkpoint directly.
    /// @return The reward token that was transferred.
    /// @return The reward amount.
    function processReward(
        address _instance,
        address _claimant,
        uint256 _checkpointTime,
        bool _isTrader
    ) external returns (IERC20, uint256);
}
