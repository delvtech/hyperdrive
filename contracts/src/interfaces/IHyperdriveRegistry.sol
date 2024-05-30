// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

interface IHyperdriveRegistry {
    /// @dev The info related to each Hyperdrive instance.
    struct HyperdriveInfo {
        /// @dev Data about the instance. Different registries can utilize
        ///      different schemas for these values.
        uint256 data;
        /// @dev The factory that deployed this instance.
        address factory;
        /// @dev The base token of the instance.
        IERC20 baseToken;
        /// @dev The vault shares token of the instance.
        IERC20 vaultSharesToken;
        /// @dev The name of the instance.
        string name;
        /// @dev The version of the instance.
        string version;
    }

    /// @notice Gets the number of Hyperdrive instances that have been registered.
    /// @return The number of registered instances.
    function getNumberOfHyperdriveInstances() external view returns (uint256);

    /// @notice Gets the registered instance at an index.
    /// @param _index The index of the instance.
    /// @return The registered instance.
    function getHyperdriveInstancesAtIndex(
        uint256 _index
    ) external view returns (address);

    /// @notice Gets the registered instances in the range of the provided
    ///         indices.
    /// @param _startIndex The start of the range.
    /// @param _endIndex The end of the range.
    /// @return The list of registered instances in the range.
    function getHyperdriveInstancesInRange(
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (address[] memory);

    /// @notice Gets the registered instances in the range of the provided
    ///         indices.
    /// @param _startIndex The start of the range.
    /// @param _endIndex The end of the range.
    /// @return The list of registered instances in the range.
    function getHyperdriveInstancesInRange(
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (address[] memory);

    /// @notice Gets the hyperdrive info for a list of instances.
    /// @param _instances The list of instances.
    /// @return The hyperdrive info.
    function getHyperdriveInfo(
        address _instances
    ) external view returns (HyperdriveInfo[] memory);
}
