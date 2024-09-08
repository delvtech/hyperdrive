// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdriveGovernedRegistryEvents } from "./IHyperdriveGovernedRegistryEvents.sol";
import { IHyperdriveRegistry } from "./IHyperdriveRegistry.sol";

interface IHyperdriveGovernedRegistry is
    IHyperdriveRegistry,
    IHyperdriveGovernedRegistryEvents
{
    /// @dev The info collected for each Hyperdrive factory.
    struct FactoryInfoInternal {
        /// @dev Data about the factory. Different registries can utilize
        ///      different schemas for these values.
        uint128 data;
        /// @dev The index of the Hyperdrive instance in the list of all of the
        ///      Hyperdrive instances.
        uint128 index;
    }

    /// @dev The info collected for each Hyperdrive instance.
    struct InstanceInfoInternal {
        /// @dev Data about the instance. Different registries can utilize
        ///      different schemas for these values.
        uint128 data;
        /// @dev The index of the Hyperdrive instance in the list of all of the
        ///      Hyperdrive instances.
        uint128 index;
        /// @dev The factory that deployed this instance.
        address factory;
    }

    /// @notice Thrown when the ending index of a range is larger than the
    ///         underlying list.
    error EndIndexTooLarge();

    /// @notice Thrown when array inputs don't have the same length.
    error InputLengthMismatch();

    /// @notice Thrown when the provided factory doesn't recognize the
    ///         corresponding Hyperdrive instance as a deployed pool.
    error InvalidFactory();

    /// @notice Thrown when the starting index of a range is larger than the
    ///         ending index.
    error InvalidIndexes();

    /// @notice Thrown when the registry has already initialized.
    error RegistryAlreadyInitialized();

    /// @notice Thrown when caller is not the admin.
    error Unauthorized();

    /// @notice Gets the initialization status of the registry.
    /// @return Gets the flag indicating whether or not the registry was
    ///         initialized.
    function isInitialized() external view returns (bool);

    /// @notice Gets the admin address of this registry.
    /// @return The admin address of this registry.
    function admin() external view returns (address);

    /// @notice Initializes the registry and sets the initial name and admin
    ///         address.
    /// @param _name The initial name.
    /// @param _admin The initial admin address.
    function initialize(string calldata _name, address _admin) external;

    /// @notice Allows the admin to transfer the admin role.
    /// @param _admin The new admin address.
    function updateAdmin(address _admin) external;

    /// @notice Allows the admin to update the name.
    /// @param _name The new name.
    function updateName(string calldata _name) external;

    /// @notice Allows the admin to set arbitrary info for Hyperdrive factories.
    /// @param __factories The Hyperdrive factories to update.
    /// @param _data The data associated with the factories.
    function setFactoryInfo(
        address[] memory __factories,
        uint128[] memory _data
    ) external;

    /// @notice Allows the admin to set arbitrary info for Hyperdrive instances.
    /// @param __instances The Hyperdrive instances to update.
    /// @param _data The data associated with the instances.
    /// @param __factories The factory associated with the instances.
    function setInstanceInfo(
        address[] memory __instances,
        uint128[] memory _data,
        address[] memory __factories
    ) external;
}
