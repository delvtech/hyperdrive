// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveFactory } from "../interfaces/IHyperdriveFactory.sol";
import { IHyperdriveGovernedRegistry } from "../interfaces/IHyperdriveGovernedRegistry.sol";
import { IHyperdriveRegistry } from "../interfaces/IHyperdriveRegistry.sol";
import { VERSION } from "../libraries/Constants.sol";

/// @author DELV
/// @title HyperdriveRegistry
/// @notice Allows a governance address to manage a list of registered
///         Hyperdrive instances. This provides a convenient place for consumers
///         of Hyperdrive contracts to query a list of well-known pools.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveRegistry is
    IHyperdriveRegistry,
    IHyperdriveGovernedRegistry
{
    /// @notice The registry's name.
    string public name;

    /// @notice The registry's version.
    string public constant version = VERSION;

    /// @notice The registry's governance address.
    address public governance;

    /// @dev A list of all of the Hyperdrive pools that have been added to the
    ///      Hyperdrive registry and have non-zero data.
    address[] internal _hyperdriveInstances;

    /// @dev A mapping from hyperdrive instances to info associated with those
    ///      instances.
    mapping(address hyperdrive => HyperdriveInfoInternal info)
        internal _hyperdriveInfo;

    /// @notice Instantiates the hyperdrive registry.
    /// @param _name The registry's name.
    constructor(string memory _name) {
        governance = msg.sender;
        name = _name;
    }

    /// @dev Ensures that the modified function is only called by governance.
    modifier onlyGovernance() {
        if (msg.sender != governance) {
            revert IHyperdriveGovernedRegistry.Unauthorized();
        }
        _;
    }

    /// @inheritdoc IHyperdriveGovernedRegistry
    function updateGovernance(
        address _governance
    ) external override onlyGovernance {
        governance = _governance;
        emit GovernanceUpdated(_governance);
    }

    /// @inheritdoc IHyperdriveGovernedRegistry
    function setHyperdriveInfo(
        address[] calldata _instances,
        uint128[] calldata _data,
        address[] calldata _factories
    ) external override onlyGovernance {
        // Ensure that the arrays have the same length.
        if (
            _instances.length != _data.length ||
            _instances.length != _factories.length
        ) {
            revert IHyperdriveRegistry.InputLengthMismatch();
        }

        // Add the Hyperdrive data to the registry.
        for (uint256 i = 0; i < _instances.length; i++) {
            // If the updated data is zero, we are deleting the entry. The
            // factory should also be zero, and we remove the entry from the
            // list of Hyperdrive instances and delete the stored info. If the
            // existing data is zero, we can simply skip this entry.
            uint256 data = _hyperdriveInfo[i].data;
            if (_data[i] == 0 && data != 0) {
                // Ensure that the factory address is zero.
                if (_factories[i] != address(0)) {
                    revert IHyperdriveRegistry.InvalidFactory();
                }

                // Remove the entry from the registry.
                _removeHyperdriveInstance(_instances[i]);
            }
            // If the updated data is non-zero and the existing data is non-zero,
            // we are updating an existing entry in the registry.
            else if (_data[i] != 0 && data != 0) {
                _updateHyperdriveInstance(
                    _instances[i],
                    _data[i],
                    _factories[i]
                );
            }
            // If the updated data is non-zero and the existing data is zero,
            // we are adding a new entry to the registry.
            else if (_data[i] != 0 && data == 0) {
                _addHyperdriveInstance(_instances[i], _data[i], _factories[i]);
            }

            // Emit an event recording the update.
            emit HyperdriveInfoUpdated(
                _hyperdriveInstance,
                _data[i],
                _factories[i]
            );
        }
    }

    /// @inheritdoc IHyperdriveRegistry
    function getNumberOfHyperdriveInstances() external view returns (uint256) {
        return _hyperdriveInstances.length;
    }

    /// @inheritdoc IHyperdriveRegistry
    function getHyperdriveInstancesInRange(
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (address[] memory instances) {
        // If the indexes are malformed, revert.
        if (startIndex > endIndex) {
            revert IHyperdriveGovernedRegistry.InvalidIndexes();
        }
        if (endIndex >= _deployerCoordinators.length) {
            revert IHyperdriveGovernedRegistry.EndIndexTooLarge();
        }

        // Get the registered instances in the range.
        instances = new address[](_endIndex - _startIndex);
        for (uint256 i = _startIndex; i < _endIndex; i++) {
            instances[i] = _hyperdriveInstances[i];
        }

        return instances;
    }

    /// @inheritdoc IHyperdriveRegistry
    function getHyperdriveInstancesAtIndex(
        uint256 _index
    ) external view returns (address) {
        return _hyperdriveInstances[_index];
    }

    /// @inheritdoc IHyperdriveRegistry
    function getHyperdriveInfo(
        address[] calldata _instances
    ) external view override returns (HyperdriveInfo[] memory info) {
        infos = new HyperdriveInfo[](_instances.length);
        for (uint256 i = 0; i < _instances.length; i++) {
            IHyperdrive instance = IHyperdrive(_instances[i]);
            IHyperdrive.PoolConfig memory config = instance.getPoolConfig();
            info[i] = HyperdriveInfo({
                data: _hyperdriveInfo[_instances[i]].data,
                factory: _hyperdriveInfo[_instances[i]].factory,
                baseToken: config.baseToken,
                vaultSharesToken: config.vaultSharesToken,
                name: instance.name(),
                version: instance.version()
            });
        }
        return info;
    }

    /// @dev Adds a new Hyperdrive instance to the registry.
    /// @param _instance The instance to add.
    /// @param _data The data associated with the new instance.
    /// @param _factory The factory that deployed the new instance.
    function _addHyperdriveInstance(
        address _instance,
        uint256 _data,
        address _factory
    ) internal {
        // Verify that the Hyperdrive instance was actually deployed by the
        // factory. If the updated factory address is zero, we skip this check.
        if (
            _factory != address(0) &&
            !IHyperdriveFactory(_factory).isInstance(_instance)
        ) {
            revert IHyperdriveGovernedRegistry.InvalidFactory();
        }

        // Add the new instance to the list of Hyperdrive instances.
        uint256 index = _hyperdriveInstances.length;
        _hyperdriveInstances.push(_instances[i]);

        // Add the entry to the mapping.
        _hyperdriveInfo[i] = HyperdriveInfoInternal({
            data: _data,
            factory: _factory,
            index: index
        });
    }

    /// @dev Adds a new Hyperdrive instance to the registry or updates an
    ///      existing Hyperdrive instance in the registry.
    /// @param _instance The Hyperdrive instance to update.
    /// @param _data The data associated with the new instance.
    /// @param _factory The factory that deployed the new instance.
    function _updateHyperdriveInstance(
        address _instance,
        uint256 _data,
        address _factory
    ) internal {
        // If the existing factory address is non-zero, we verify that
        // the updated factory address is the same. Otherwise, if the
        // updated factory address is non-zero, verify that the
        // Hyperdrive instance was actually deployed by the factory. If
        // the updated factory address is zero, we skip this check.
        address factory = _hyperdriveInfo[_instance].factory;
        if (
            (factory != 0 && factory != _factory) ||
            (factory == 0 &&
                _factory != address(0) &&
                !IHyperdriveFactory(_factory).isInstance(_instance))
        ) {
            revert IHyperdriveGovernedRegistry.InvalidFactory();
        }

        // Update the entry in the mapping.
        _hyperdriveInfo[i] = HyperdriveInfoInternal({
            data: _data,
            factory: _factory,
            index: _hyperdriveInfo[_instance].index
        });
    }

    /// @dev Removes a Hyperdrive instance from the registry.
    /// @param _instance The Hyperdrive instance to remove.
    function _removeHyperdriveInstance(address _instance) internal {
        // Delete the entry from the instances list.
        _hyperdriveInstances[
            _hyperdriveInfo[_instance].index
        ] = _hyperdriveInstances.pop();

        // Delete the entry from the mapping.
        delete _hyperdriveInfo[_instance];
    }
}
