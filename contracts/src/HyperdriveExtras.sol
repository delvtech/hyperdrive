// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveStorage } from "./HyperdriveStorage.sol";

// FIXME: If we don't end up needing to add things to this, we should rename this
// to HyperdriveAdmin.
//
// FIXME: Is this a good time to start using the `Authorizable` pattern?
//
/// @author DELV
/// @title HyperdriveExtras
/// @notice The Hyperdrive extras contract. This is a logic contract for the
///         Hyperdrive system that includes stateful functions that are called
///         infrequently.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveExtras is HyperdriveStorage {
    event CollectGovernanceFee(address indexed collector, uint256 fees);

    event GovernanceUpdated(address indexed newGovernance);

    event PauserUpdated(address indexed newPauser);

    /// @notice Initializes a Hyperdrive extras instance.
    /// @param _config The configuration for the pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveStorage(_config) {}

    /// Yield Source ///

    /// @notice Withdraws shares from the yield source and sends the base
    ///         released to the destination.
    /// @param _shares The shares to withdraw from the yield source.
    /// @param _options The options that configure how the withdrawal is
    ///        settled. In particular, the destination and currency used in the
    ///        withdrawal are specified here. Aside from those options, yield
    ///        sources can choose to implement additional options.
    /// @return amountWithdrawn The amount of base released by the withdrawal.
    function _withdraw(
        uint256 _shares,
        IHyperdrive.Options calldata _options
    ) internal virtual returns (uint256 amountWithdrawn);

    /// Admin ///

    /// @notice This function collects the governance fees accrued by the pool.
    /// @param _options The options that configure how the fees are settled.
    /// @return proceeds The amount of base collected.
    function collectGovernanceFee(
        IHyperdrive.Options calldata _options
    ) external nonReentrant returns (uint256 proceeds) {
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
        emit CollectGovernanceFee(_feeCollector, proceeds);
    }

    /// @notice Allows an authorized address to pause this contract.
    /// @param _status True to pause all deposits and false to unpause them.
    function pause(bool _status) external {
        if (!_pausers[msg.sender]) revert IHyperdrive.Unauthorized();
        _marketState.isPaused = _status;
    }

    /// @notice Allows governance to change governance.
    /// @param _who The new governance address.
    function setGovernance(address _who) external {
        if (msg.sender != _governance) revert IHyperdrive.Unauthorized();
        _governance = _who;

        emit GovernanceUpdated(_who);
    }

    /// @notice Allows governance to change the pauser status of an address.
    /// @param who The address to change.
    /// @param status The new pauser status.
    function setPauser(address who, bool status) external {
        if (msg.sender != _governance) revert IHyperdrive.Unauthorized();
        _pausers[who] = status;
        emit PauserUpdated(who);
    }
}
