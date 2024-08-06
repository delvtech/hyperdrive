// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IHyperdriveRegistry {
    /// @dev The info collected for each Hyperdrive factory.
    struct FactoryInfo {
        /// @dev Data about the factory. Different registries can utilize
        ///      different schemas for these values.
        uint256 data;
    }

    /// @dev The info collected for each Hyperdrive factory along with the
    ///      metadata associated with each instance.
    struct FactoryInfoWithMetadata {
        /// @dev Data about the factory. Different registries can utilize
        ///      different schemas for these values.
        uint256 data;
        /// @dev The factory's name.
        string name;
        /// @dev The factory's kind.
        string kind;
        /// @dev The factory's version.
        string version;
    }

    /// @dev The info related to each Hyperdrive instance.
    struct InstanceInfo {
        /// @dev Data about the instance. Different registries can utilize
        ///      different schemas for these values.
        uint256 data;
        /// @dev The factory that deployed this instance.
        address factory;
    }

    /// @dev The info related to each Hyperdrive instance along with the
    ///      metadata associated with each instance.
    struct InstanceInfoWithMetadata {
        /// @dev Data about the instance. Different registries can utilize
        ///      different schemas for these values.
        uint256 data;
        /// @dev The factory that deployed this instance.
        address factory;
        /// @dev The instance's name.
        string name;
        /// @dev The instance's kind.
        string kind;
        /// @dev The instance's version.
        string version;
    }

    /// @notice Gets the registry's name.
    /// @return The registry's name.
    function name() external view returns (string memory);

    /// @notice Gets the registry's kind.
    /// @return The registry's kind.
    function kind() external pure returns (string memory);

    /// @notice Gets the registry's version.
    /// @return The registry's version.
    function version() external pure returns (string memory);

    /// @notice Gets the number of Hyperdrive factories that have been registered.
    /// @return The number of registered factories.
    function getNumberOfFactories() external view returns (uint256);

    /// @notice Gets the registered factory at an index.
    /// @param _index The index of the factory.
    /// @return The registered factory.
    function getFactoryAtIndex(uint256 _index) external view returns (address);

    /// @notice Gets the registered factories in the range of the provided
    ///         indices.
    /// @param _startIndex The start of the range (inclusive).
    /// @param _endIndex The end of the range (exclusive).
    /// @return The list of registered factories in the range.
    function getFactoriesInRange(
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (address[] memory);

    /// @notice Gets the Hyperdrive factory info for a factory.
    /// @param _factory The factory.
    /// @return The factory info.
    function getFactoryInfo(
        address _factory
    ) external view returns (FactoryInfo memory);

    /// @notice Gets the Hyperdrive factory info for a list of factories.
    /// @param __factories The list of factories.
    /// @return The list of factory info.
    function getFactoryInfos(
        address[] calldata __factories
    ) external view returns (FactoryInfo[] memory);

    /// @notice Gets the Hyperdrive factory info with associated metadata for a
    ///         factory.
    /// @param _factory The factory.
    /// @return The factory info with associated metadata.
    function getFactoryInfoWithMetadata(
        address _factory
    ) external view returns (FactoryInfoWithMetadata memory);

    /// @notice Gets the Hyperdrive factory info with associated metadata for a
    ///         list of factories.
    /// @param __factories The list of factories.
    /// @return The list of factory info with associated metadata.
    function getFactoryInfosWithMetadata(
        address[] calldata __factories
    ) external view returns (FactoryInfoWithMetadata[] memory);

    /// @notice Gets the number of Hyperdrive instances that have been registered.
    /// @return The number of registered instances.
    function getNumberOfInstances() external view returns (uint256);

    /// @notice Gets the registered instance at an index.
    /// @param _index The index of the instance.
    /// @return The registered instance.
    function getInstanceAtIndex(uint256 _index) external view returns (address);

    /// @notice Gets the registered instances in the range of the provided
    ///         indices.
    /// @param _startIndex The start of the range (inclusive).
    /// @param _endIndex The end of the range (exclusive).
    /// @return The list of registered instances in the range.
    function getInstancesInRange(
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (address[] memory);

    /// @notice Gets the instance info for an instance.
    /// @param _instance The instance.
    /// @return The instance info.
    function getInstanceInfo(
        address _instance
    ) external view returns (InstanceInfo memory);

    /// @notice Gets the instance info for a list of instances.
    /// @param __instances The list of instances.
    /// @return The list of instance info.
    function getInstanceInfos(
        address[] calldata __instances
    ) external view returns (InstanceInfo[] memory);

    /// @notice Gets the instance info with associated metadata for an instance.
    /// @param _instance The instance.
    /// @return The instance info with associated metadata.
    function getInstanceInfoWithMetadata(
        address _instance
    ) external view returns (InstanceInfoWithMetadata memory);

    /// @notice Gets the instance info with associated metadata for a list of
    ///         instances.
    /// @param __instances The list of instances.
    /// @return The list of instance info with associated metadata.
    function getInstanceInfosWithMetadata(
        address[] calldata __instances
    ) external view returns (InstanceInfoWithMetadata[] memory);
}
