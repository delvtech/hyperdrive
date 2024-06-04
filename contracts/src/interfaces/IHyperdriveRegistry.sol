// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

interface IHyperdriveRegistry {
    /// @dev The info collected for each Hyperdrive factory.
    struct FactoryInfo {
        /// @dev Data about the factory. Different registries can utilize
        ///      different schemas for these values.
        uint256 data;
    }

    /// @dev The info related to each Hyperdrive instance.
    struct InstanceInfo {
        /// @dev Data about the instance. Different registries can utilize
        ///      different schemas for these values.
        uint256 data;
        /// @dev The factory that deployed this instance.
        address factory;
    }

    /// @notice Gets the registry's name.
    /// @return The registry's name.
    function name() external view returns (string memory);

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

    /// @notice Gets the hyperdrive factory info for a list of factories.
    /// @param __factories The list of factories.
    /// @return The hyperdrive factory info.
    function getFactoryInfo(
        address[] calldata __factories
    ) external view returns (FactoryInfo[] memory);

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

    /// @notice Gets the hyperdrive info for a list of instances.
    /// @param __instances The list of instances.
    /// @return The hyperdrive info.
    function getInstanceInfo(
        address[] calldata __instances
    ) external view returns (InstanceInfo[] memory);
}
