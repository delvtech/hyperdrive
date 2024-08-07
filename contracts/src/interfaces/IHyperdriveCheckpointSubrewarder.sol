// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

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

    /// @notice Allows the admin to transfer the admin role.
    /// @param _admin The new admin address.
    function updateAdmin(address _admin) external;

    /// @notice Allows the admin to update the source address that supplies the
    ///         rewards.
    /// @param _source The new source address that will supply the rewards.
    function updateSource(address _source) external;

    /// @notice Allows the admin to update the reward token.
    /// @param _rewardToken The new reward token.
    function updateRewardToken(IERC20 _rewardToken) external;

    /// @notice Allows the admin to update the registry.
    /// @param _registry The new registry.
    function updateRegistry(IHyperdriveRegistry _registry) external;

    /// @notice Allows the admin to update the minter reward amount.
    /// @param _minterRewardAmount The new minter reward amount.
    function updateMinterRewardAmount(uint256 _minterRewardAmount) external;

    /// @notice Allows the admin to update the trader reward amount.
    /// @param _traderRewardAmount The new trader reward amount.
    function updateTraderRewardAmount(uint256 _traderRewardAmount) external;

    /// @notice Processes a checkpoint reward.
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

    /// @notice Gets the subrewarder's name.
    /// @return The subrewarder's name.
    function name() external view returns (string memory);

    /// @notice Gets the subrewarder's kind.
    /// @return The subrewarder's kind.
    function kind() external pure returns (string memory);

    /// @notice Gets the subrewarder's version.
    /// @return The subrewarder's version.
    function version() external pure returns (string memory);

    /// @notice Gets the rewarder address that can delegate to this subrewarder.
    /// @return The rewarder address.
    function rewarder() external view returns (address);

    /// @notice Gets the admin address.
    /// @return The admin address.
    function admin() external view returns (address);

    /// @notice Gets the address that is the source for the reward funds.
    /// @return The source address.
    function source() external view returns (address);

    /// @notice Gets the associated registry. This is what will be used to
    ///         determine which instances should receive checkpoint rewards.
    /// @return The registry address.
    function registry() external view returns (IHyperdriveRegistry);

    /// @notice Gets the reward token.
    /// @return The reward token.
    function rewardToken() external view returns (IERC20);

    /// @notice Gets the minter reward amount. This is the reward amount paid
    ///         when checkpoints are minted through the `checkpoint` function.
    /// @return The minter reward amount.
    function minterRewardAmount() external view returns (uint256);

    /// @notice Gets the trader reward amount. This is the reward amount paid
    ///         when checkpoints are minted through `openLong`, `openShort`,
    ///         `closeLong`, `closeShort`, `addLiquidity`, `removeLiquidity`, or
    ///         `redeemWithdrawalShares`.
    function traderRewardAmount() external view returns (uint256);
}
