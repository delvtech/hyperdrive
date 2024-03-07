// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

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
        if (_options.destination != _feeCollector) {
            revert IHyperdrive.InvalidFeeDestination();
        }

        // Ensure that the caller is authorized to collect fees.
        if (
            !_pausers[msg.sender] &&
            msg.sender != _feeCollector &&
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
            _feeCollector,
            _convertToBaseFromOption(proceeds, vaultSharePrice, _options)
        );
    }

    /// @dev Allows an authorized address to pause this contract.
    /// @param _status True to pause all deposits and false to unpause them.
    function _pause(bool _status) internal {
        // Ensure that the sender is authorized to pause the contract.
        if (!_pausers[msg.sender]) {
            revert IHyperdrive.Unauthorized();
        }

        // Update the paused status and emit an event.
        _marketState.isPaused = _status;
        emit PauseStatusUpdated(_status);
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
}
