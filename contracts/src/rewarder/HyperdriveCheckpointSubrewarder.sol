// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveCheckpointSubrewarder } from "../interfaces/IHyperdriveCheckpointSubrewarder.sol";
import { IHyperdriveRegistry } from "../interfaces/IHyperdriveRegistry.sol";
import { HYPERDRIVE_CHECKPOINT_SUBREWARDER_KIND, VERSION } from "../libraries/Constants.sol";

/// @author DELV
/// @notice A checkpoint subrewarder that pays a fixed amount for checkpoints
///         minted by contracts that are listed within an associated registry.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveCheckpointSubrewarder is IHyperdriveCheckpointSubrewarder {
    using SafeERC20 for ERC20;

    /// @notice The checkpoint subrewarder's name.
    string public name;

    /// @notice The checkpoint subrewarder's kind.
    string public constant kind = HYPERDRIVE_CHECKPOINT_SUBREWARDER_KIND;

    /// @notice The checkpoint subrewarder's version.
    string public constant version = VERSION;

    /// @notice The rewarder address that can delegate to this subrewarder.
    address public immutable rewarder;

    /// @notice The admin address.
    address public admin;

    /// @notice The address that is the source for the reward funds.
    address public source;

    /// @notice The associated registry. This is what will be used to determine
    ///         which instances should receive checkpoint rewards.
    IHyperdriveRegistry public registry;

    /// @notice The reward token.
    IERC20 public rewardToken;

    /// @notice The non-trader reward amount.
    uint256 public minterRewardAmount;

    /// @notice The trader reward amount.
    uint256 public traderRewardAmount;

    /// @notice Instantiates the hyperdrive checkpoint rewarder.
    /// @param _name The checkpoint rewarder's name.
    /// @param _rewarder The address of the rewarder.
    /// @param _source The address of the source.
    /// @param _registry The address of the registry.
    /// @param _rewardToken The address of the reward token.
    /// @param _minterRewardAmount The minter reward amount.
    /// @param _traderRewardAmount The trader reward amount.
    constructor(
        string memory _name,
        address _rewarder,
        address _source,
        IHyperdriveRegistry _registry,
        IERC20 _rewardToken,
        uint256 _minterRewardAmount,
        uint256 _traderRewardAmount
    ) {
        name = _name;
        admin = msg.sender;
        rewarder = _rewarder;
        source = _source;
        registry = _registry;
        rewardToken = _rewardToken;
        minterRewardAmount = _minterRewardAmount;
        traderRewardAmount = _traderRewardAmount;
    }

    /// @dev Ensures that the modified function is only called by the admin.
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert IHyperdriveCheckpointSubrewarder.Unauthorized();
        }
        _;
    }

    /// @dev Ensures that the modified function is only called by the rewarder.
    modifier onlyRewarder() {
        if (msg.sender != rewarder) {
            revert IHyperdriveCheckpointSubrewarder.Unauthorized();
        }
        _;
    }

    /// @inheritdoc IHyperdriveCheckpointSubrewarder
    function updateAdmin(address _admin) external onlyAdmin {
        admin = _admin;
        emit AdminUpdated(_admin);
    }

    /// @inheritdoc IHyperdriveCheckpointSubrewarder
    function updateSource(address _source) external onlyAdmin {
        source = _source;
        emit SourceUpdated(_source);
    }

    /// @inheritdoc IHyperdriveCheckpointSubrewarder
    function updateRewardToken(IERC20 _rewardToken) external onlyAdmin {
        rewardToken = _rewardToken;
        emit RewardTokenUpdated(_rewardToken);
    }

    /// @inheritdoc IHyperdriveCheckpointSubrewarder
    function updateRegistry(IHyperdriveRegistry _registry) external onlyAdmin {
        registry = _registry;
        emit RegistryUpdated(_registry);
    }

    /// @inheritdoc IHyperdriveCheckpointSubrewarder
    function updateMinterRewardAmount(
        uint256 _minterRewardAmount
    ) external onlyAdmin {
        minterRewardAmount = _minterRewardAmount;
        emit MinterRewardAmountUpdated(_minterRewardAmount);
    }

    /// @inheritdoc IHyperdriveCheckpointSubrewarder
    function updateTraderRewardAmount(
        uint256 _traderRewardAmount
    ) external onlyAdmin {
        traderRewardAmount = _traderRewardAmount;
        emit TraderRewardAmountUpdated(_traderRewardAmount);
    }

    /// @inheritdoc IHyperdriveCheckpointSubrewarder
    function processReward(
        address _instance,
        address _claimant,
        uint256 _checkpointTime,
        bool _isTrader
    ) external onlyRewarder returns (IERC20, uint256) {
        // If the checkpoint time isn't the latest checkpoint time, the reward
        // is zero.
        IERC20 rewardToken_ = rewardToken;
        if (
            _checkpointTime !=
            HyperdriveMath.calculateCheckpointTime(
                block.timestamp,
                IHyperdrive(_instance).getPoolConfig().checkpointDuration
            )
        ) {
            return (rewardToken_, 0);
        }

        // If the instance doesn't have a status of 1 in the registry, the
        // reward is zero.
        if (registry.getInstanceInfo(_instance).data != 1) {
            return (rewardToken_, 0);
        }

        // If the reward is non-zero, we reward the minter.
        uint256 rewardAmount = _isTrader
            ? traderRewardAmount
            : minterRewardAmount;
        if (rewardAmount > 0) {
            ERC20(address(rewardToken_)).safeTransferFrom(
                source,
                _claimant,
                rewardAmount
            );
        }

        return (rewardToken_, rewardAmount);
    }
}
