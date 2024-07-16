// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

interface IEverlongAdmin {
    /// @notice Emitted when admin is transferred.
    event AdminUpdated(address indexed admin);

    /// @notice Thrown when caller is not the admin.
    error Unauthorized();

    /// @notice Gets the admin address of the Everlong instance.
    /// @return The admin address of this Everlong instance.
    function admin() external view returns (address);

    /// @notice Allows admin to transfer the admin role.
    /// @param _admin The new admin address.
    function setAdmin(address _admin) external;
}
