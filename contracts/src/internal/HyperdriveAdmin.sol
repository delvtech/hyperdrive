// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveEvents } from "../interfaces/IHyperdriveEvents.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";

/// @author DELV
/// @title HyperdriveAdmin
/// @notice The Hyperdrive admin contract. This contract provides functions that
///         governance can use to pause the pool and update permissions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveAdmin is IHyperdriveEvents, HyperdriveBase {
    using SafeERC20 for ERC20;

    /// @dev This function collects the governance fees accrued by the pool.
    /// @param _options The options that configure how the fees are settled.
    /// @return proceeds The governance fees collected. The units of this
    ///         quantity are either base or vault shares, depending on the value
    ///         of `_options.asBase`.
    function _collectGovernanceFee(
        IHyperdrive.Options calldata _options
    ) internal nonReentrant returns (uint256 proceeds) {
        // Check that the provided options are valid.
        _checkOptions(_options);

        // Ensure that the destination is set to the fee collector.
        address feeCollector = _feeCollector;
        if (_options.destination != feeCollector) {
            revert IHyperdrive.InvalidFeeDestination();
        }

        // Ensure that the caller is authorized to collect fees.
        if (
            !_pausers[msg.sender] &&
            msg.sender != feeCollector &&
            msg.sender != _governance
        ) {
            revert IHyperdrive.Unauthorized();
        }

        // Withdraw the accrued governance fees to the fee collector.
        uint256 vaultSharePrice = _pricePerVaultShare();
        uint256 governanceFeesAccrued = _governanceFeesAccrued;
        delete _governanceFeesAccrued;
        proceeds = _withdraw(governanceFeesAccrued, vaultSharePrice, _options);
        emit CollectGovernanceFee(
            feeCollector,
            proceeds,
            vaultSharePrice,
            _options.asBase
        );
    }

    /// @dev Allows an authorized address to pause this contract.
    /// @param _status True to pause all deposits and false to unpause them.
    function _pause(bool _status) internal {
        // Ensure that the sender is authorized to pause the contract.
        if (!_pausers[msg.sender] && msg.sender != _governance) {
            revert IHyperdrive.Unauthorized();
        }

        // Update the paused status and emit an event.
        _marketState.isPaused = _status;
        emit PauseStatusUpdated(_status);
    }

    /// @dev Allows governance to transfer the fee collector role.
    /// @param _who The new fee collector.
    function _setFeeCollector(address _who) internal {
        // Ensure that the sender is governance.
        if (msg.sender != _governance) {
            revert IHyperdrive.Unauthorized();
        }

        // Update the governance address and emit an event.
        _feeCollector = _who;
        emit FeeCollectorUpdated(_who);
    }

    /// @dev Allows governance to transfer the sweep collector role.
    /// @param _who The new fee collector.
    function _setSweepCollector(address _who) internal {
        // Ensure that the sender is governance.
        if (msg.sender != _governance) {
            revert IHyperdrive.Unauthorized();
        }

        // Update the sweep collector address and emit an event.
        _sweepCollector = _who;
        emit SweepCollectorUpdated(_who);
    }

    /// @dev Allows governance to transfer the checkpoint rewarder.
    /// @param _newCheckpointRewarder The new checkpoint rewarder.
    function _setCheckpointRewarder(address _newCheckpointRewarder) internal {
        // Ensure that the sender is governance.
        if (msg.sender != _governance) {
            revert IHyperdrive.Unauthorized();
        }

        // Update the checkpoint rewarder address and emit an event.
        _checkpointRewarder = _newCheckpointRewarder;
        emit CheckpointRewarderUpdated(_checkpointRewarder);
    }

    /// @dev Allows governance to transfer the governance role.
    /// @param _who The new governance address.
    function _setGovernance(address _who) internal {
        // Ensure that the sender is governance.
        if (msg.sender != _governance) {
            revert IHyperdrive.Unauthorized();
        }

        // Update the governance address and emit an event.
        _governance = _who;
        emit GovernanceUpdated(_who);
    }

    /// @dev Allows governance to change the pauser status of an address.
    /// @param _who The address to change.
    /// @param _status The new pauser status.
    function _setPauser(address _who, bool _status) internal {
        // Ensure that the sender is governance.
        if (msg.sender != _governance) {
            revert IHyperdrive.Unauthorized();
        }

        // Update the pauser status and emit an event.
        _pausers[_who] = _status;
        emit PauserUpdated(_who, _status);
    }

    /// @dev Transfers the contract's balance of a target token to the sweep
    ///      collector address.
    /// @dev WARN: It is unlikely but possible that there is a selector overlap
    ///      with 'transfer'. Any integrating contracts should be checked
    ///      for that, as it may result in an unexpected call from this address.
    /// @param _target The target token to sweep.
    function _sweep(IERC20 _target) internal nonReentrant {
        // Ensure that the caller is authorized to sweep tokens.
        address sweepCollector = _sweepCollector;
        if (
            !_pausers[msg.sender] &&
            msg.sender != sweepCollector &&
            msg.sender != _governance
        ) {
            revert IHyperdrive.Unauthorized();
        }

        // Gets the Hyperdrive's balance of vault shares prior to
        // sweeping.
        uint256 shareBalance = _totalShares();

        // Transfer the entire balance of the sweep target to the sweep
        // collector.
        uint256 balance = _target.balanceOf(address(this));
        ERC20(address(_target)).safeTransfer(sweepCollector, balance);

        // Ensure that the vault shares balance hasn't changed.
        if (_totalShares() != shareBalance) {
            revert IHyperdrive.SweepFailed();
        }

        emit Sweep(sweepCollector, address(_target));
    }
}
