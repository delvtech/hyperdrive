// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";

/// @author DELV
/// @title HyperdriveAdmin
/// @notice The Hyperdrive admin contract. This contract provides functions that
///         governance can use to pause the pool and update permissions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveAdmin is HyperdriveBase {
    event CollectGovernanceFee(address indexed collector, uint256 fees);

    event GovernanceUpdated(address indexed newGovernance);

    event PauserUpdated(address indexed newPauser);

    /// @dev This function collects the governance fees accrued by the pool.
    /// @param _options The options that configure how the fees are settled.
    /// @return proceeds The amount collected in units specified by _options.
    function _collectGovernanceFee(
        IHyperdrive.Options calldata _options
    ) internal nonReentrant returns (uint256 proceeds) {
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
        uint256 governanceFeesAccrued = _governanceFeesAccrued;
        delete _governanceFeesAccrued;
        proceeds = _withdraw(governanceFeesAccrued, _options);
        emit CollectGovernanceFee(
            _feeCollector,
            _convertToBaseFromOption(proceeds, _pricePerVaultShare(), _options)
        );
    }

    /// @dev Allows an authorized address to pause this contract.
    /// @param _status True to pause all deposits and false to unpause them.
    function _pause(bool _status) internal {
        if (!_pausers[msg.sender]) revert IHyperdrive.Unauthorized();
        _marketState.isPaused = _status;
    }

    /// @dev Allows governance to change governance.
    /// @param _who The new governance address.
    function _setGovernance(address _who) internal {
        if (msg.sender != _governance) revert IHyperdrive.Unauthorized();
        _governance = _who;

        emit GovernanceUpdated(_who);
    }

    /// @dev Allows governance to change the pauser status of an address.
    /// @param who The address to change.
    /// @param status The new pauser status.
    function _setPauser(address who, bool status) internal {
        if (msg.sender != _governance) revert IHyperdrive.Unauthorized();
        _pausers[who] = status;
        emit PauserUpdated(who);
    }
}
