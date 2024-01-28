// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

interface IHyperdriveRegistry {
    /// @notice Allows anyone to get the info for a hyperdrive instance.
    /// @param _hyperdriveInstance The hyperdrive instance address.
    /// @return The uint256 value set by governance.
    function getHyperdriveInfo(
        address _hyperdriveInstance
    ) external view returns (uint256);
}
