// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdriveRegistry } from "./IHyperdriveRegistry.sol";

interface IHyperdriveGovernedRegistry is IHyperdriveRegistry {
    /// @notice Emitted when admin is transferred.
    event AdminUpdated(address indexed admin);

    /// @notice Emitted when Hyperdrive factory info is updated.
    event FactoryInfoUpdated(address indexed factory, uint256 indexed data);

    /// @notice Emitted when Hyperdrive instance info is updated.
    event InstanceInfoUpdated(
        address indexed instance,
        uint256 indexed data,
        address indexed factory
    );

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

    /// @notice Thrown when caller is not the admin.
    error Unauthorized();

    /// @notice Gets the admin address of this registry.
    /// @return The admin address of this registry.
    function admin() external view returns (address);

    /// @notice Allows admin to transfer the admin role.
    /// @param _admin The new admin address.
    function updateAdmin(address _admin) external;

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
