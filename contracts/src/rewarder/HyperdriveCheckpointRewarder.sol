// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC20 } from "../interfaces/IERC20.sol";
import { IHyperdriveCheckpointRewarder } from "../interfaces/IHyperdriveCheckpointRewarder.sol";
import { IHyperdriveCheckpointSubrewarder } from "../interfaces/IHyperdriveCheckpointSubrewarder.sol";
import { VERSION } from "../libraries/Constants.sol";

/// @author DELV
/// @notice A checkpoint rewarder that is controlled by an admin and delegates
///         it's reward functionality to a subrewarder.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveCheckpointRewarder is IHyperdriveCheckpointRewarder {
    /// @notice The checkpoint rewarder's name.
    string public name;

    /// @notice The checkpoint rewarder's version.
    string public constant version = VERSION;

    /// @notice The checkpoint rewarder's admin address.
    address public admin;

    // @notice The rewarder address that will be delegated to.
    IHyperdriveCheckpointSubrewarder public subrewarder;

    /// @notice Instantiates the hyperdrive checkpoint rewarder.
    /// @param _name The checkpoint rewarder's name.
    constructor(string memory _name) {
        admin = msg.sender;
        name = _name;
    }

    /// @dev Ensures that the modified function is only called by the admin.
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert IHyperdriveCheckpointRewarder.Unauthorized();
        }
        _;
    }

    /// @notice Allows the admin to transfer the admin role.
    /// @param _admin The new admin address.
    function updateAdmin(address _admin) external onlyAdmin {
        admin = _admin;
        emit AdminUpdated(_admin);
    }

    /// @notice Allows the admin to update the subrewarder.
    /// @param _subrewarder The rewarder that will be delegated to.
    function updateSubrewarder(
        IHyperdriveCheckpointSubrewarder _subrewarder
    ) external onlyAdmin {
        subrewarder = _subrewarder;
        emit SubrewarderUpdated(_subrewarder);
    }

    /// @notice Claims a checkpoint reward.
    /// @param _claimant The address that is claiming the checkpoint reward.
    /// @param _checkpointTime The time of the checkpoint that was minted.
    /// @param _isTrader A boolean indicating whether or not the checkpoint was
    ///        minted by a trader or by someone calling checkpoint directly.
    function claimCheckpointReward(
        address _claimant,
        uint256 _checkpointTime,
        bool _isTrader
    ) external {
        // Process the reward.
        (IERC20 rewardToken, uint256 rewardAmount) = subrewarder.processReward(
            msg.sender,
            _claimant,
            _checkpointTime,
            _isTrader
        );

        // If the reward amount is greater than zero, emit an event.
        if (rewardAmount > 0) {
            emit CheckpointRewardClaimed(
                msg.sender,
                _claimant,
                _isTrader,
                _checkpointTime,
                rewardToken,
                rewardAmount
            );
        }
    }
}