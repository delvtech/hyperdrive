// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdriveRegistry } from "./IHyperdriveRegistry.sol";

interface IHyperdriveGovernedRegistry is IHyperdriveRegistry {
    /// @notice Emitted when governance is transferred.
    event GovernanceUpdated(address indexed governance);

    /// @notice Emitted when hyperdrive info is updated.
    event HyperdriveInfoUpdated(address indexed hyperdrive, uint256 data);

    /// @notice Thrown when caller is not governance.
    error Unauthorized();

    /// @notice Allows governance to transfer the governance role.
    /// @param _governance The new governance address.
    function updateGovernance(address _governance) external;

    /// @notice Allows governance to set arbitrary info for a Hyperdrive
    ///         instance.
    /// @param _hyperdriveInstance The Hyperdrive instance address.
    /// @param _data The uint256 value to be set to convey information about the
    ///        instance.
    function setHyperdriveInfo(
        address _hyperdriveInstance,
        uint256 _data
    ) external;
}
