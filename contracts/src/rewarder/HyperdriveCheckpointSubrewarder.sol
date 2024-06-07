// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IHyperdriveCheckpointSubrewarder } from "../interfaces/IHyperdriveCheckpointSubrewarder.sol";
import { IHyperdriveRegistry } from "../interfaces/IHyperdriveRegistry.sol";
import { VERSION } from "../libraries/Constants.sol";

/// @author DELV
/// @notice A checkpoint subrewarder that pays a fixed amount for checkpoints
///         minted by contracts that are listed within an associated registry.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveCheckpointSubrewarder is IHyperdriveCheckpointSubrewarder {
    using SafeERC20 for ERC20;

    /// @notice The checkpoint rewarder's name.
    string public name;

    /// @notice The checkpoint rewarder's version.
    string public constant version = VERSION;

    /// @notice The rewarder address that can delegate to this subrewarder.
    address public immutable rewarder;

    /// @notice The checkpoint rewarder's admin address.
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
    /// @param _registry The address of the registry.
    constructor(
        string memory _name,
        address _rewarder,
        IHyperdriveRegistry _registry
    ) {
        admin = msg.sender;
        rewarder = _rewarder;
        registry = _registry;
        name = _name;
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

    /// @notice Allows the admin to transfer the admin role.
    /// @param _admin The new admin address.
    function updateAdmin(address _admin) external onlyAdmin {
        admin = _admin;
        emit AdminUpdated(_admin);
    }

    /// @notice Allows the admin to update the registry.
    /// @param _registry The new registry.
    function updateRegistry(IHyperdriveRegistry _registry) external onlyAdmin {
        registry = _registry;
        emit RegistryUpdated(_registry);
    }

    /// @notice Allows the admin to update the reward token.
    /// @param _rewardToken The new reward token.
    function updateRewardToken(IERC20 _rewardToken) external onlyAdmin {
        rewardToken = _rewardToken;
        emit RewardTokenUpdated(_rewardToken);
    }

    /// @notice Allows the admin to update the source.
    /// @param _source The new source.
    function updateSource(address _source) external onlyAdmin {
        source = _source;
        emit SourceUpdated(_source);
    }

    /// @notice Allows the admin to update the trader reward amount.
    /// @param _traderRewardAmount The new trader reward amount.
    function updateTraderRewardAmount(
        uint256 _traderRewardAmount
    ) external onlyAdmin {
        traderRewardAmount = _traderRewardAmount;
        emit TraderRewardAmountUpdated(_traderRewardAmount);
    }

    /// @notice Allows the admin to update the minter reward amount.
    /// @param _minterRewardAmount The new minter reward amount.
    function updateMinterRewardAmount(
        uint256 _minterRewardAmount
    ) external onlyAdmin {
        minterRewardAmount = _minterRewardAmount;
        emit MinterRewardAmountUpdated(_minterRewardAmount);
    }

    /// @notice Processes a checkpoint reward.
    /// @param _instance The instance that submitted the claim.
    /// @param _claimant The address that is claiming the checkpoint reward.
    /// @param _isTrader A boolean indicating whether or not the checkpoint was
    ///        minted by a trader or by someone calling checkpoint directly.
    function processReward(
        address _instance,
        address _claimant,
        uint256, // unused
        bool _isTrader
    ) external onlyRewarder returns (IERC20, uint256) {
        // FIXME
        // If the instance has a status of 1 in the registry, the reward is
        // the trader or minter reward amount. Otherwise, it's zero.
        uint256 rewardAmount;
        if (registry.getInstanceInfo(_instance).data == 1) {
            rewardAmount = _isTrader ? traderRewardAmount : minterRewardAmount;
        }

        // If the reward is non-zero, we reward the minter.
        if (rewardAmount > 0) {
            ERC20(address(rewardToken)).safeTransferFrom(
                source,
                _claimant,
                rewardAmount
            );
        }

        return (rewardToken, rewardAmount);
    }
}
