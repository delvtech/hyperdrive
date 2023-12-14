// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

interface IHyperdriveRegistry {
    /// @notice Emitted when governance is transferred.
    event GovernanceUpdated(address indexed governance);

    /// @notice Emitted when hyperdrive info is updated.
    event HyperdriveInfoUpdated(address indexed hyperdrive, uint256 data);

    /// @notice Allows governance to transfer the governance role.
    /// @param _governance The new governance address.
    function updateGovernance(address _governance) external;

    /// @notice Allows governance set arbitrary info for a hyperdrive instance.
    /// @param _hyperdriveInstance The hyperdrive instance address.
    /// @param _data The uint256 value to be set to convey information about the instance.
    function setHyperdriveInfo(address _hyperdriveInstance, uint256 _data) external;

    /// @notice Allows anyone to get the info for a hyperdrive instance.
    /// @param _hyperdriveInstance The hyperdrive instance address.
    /// @return The uint256 value set by governance.
    function getHyperdriveInfo(address _hyperdriveInstance) external view returns (uint256);

}
