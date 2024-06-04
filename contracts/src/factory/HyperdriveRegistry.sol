// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

// FIXME
import { console2 as console } from "forge-std/console2.sol";

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveFactory } from "../interfaces/IHyperdriveFactory.sol";
import { IHyperdriveGovernedRegistry } from "../interfaces/IHyperdriveGovernedRegistry.sol";
import { IHyperdriveRegistry } from "../interfaces/IHyperdriveRegistry.sol";
import { VERSION } from "../libraries/Constants.sol";
import { SafeCast } from "../libraries/SafeCast.sol";

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
    using SafeCast for *;

    /// @notice The registry's name.
    string public name;

    /// @notice The registry's version.
    string public constant version = VERSION;

    /// @notice The registry's admin address.
    address public admin;

    /// @dev A list of all of the Hyperdrive factories that have been added to
    ///      the Hyperdrive registry.
    address[] internal _hyperdriveFactories;

    /// @dev A mapping from hyperdrive factories to info associated with those
    ///      factories.
    mapping(address factory => FactoryInfoInternal info) internal _factoryInfo;

    /// @dev A list of all of the Hyperdrive instances that have been added to
    ///      the Hyperdrive registry.
    address[] internal _hyperdriveInstances;

    /// @dev A mapping from hyperdrive instances to info associated with those
    ///      instances.
    mapping(address hyperdrive => HyperdriveInfoInternal info)
        internal _hyperdriveInfo;

    /// @notice Instantiates the hyperdrive registry.
    /// @param _name The registry's name.
    constructor(string memory _name) {
        admin = msg.sender;
        name = _name;
    }

    /// @dev Ensures that the modified function is only called by the admin.
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert IHyperdriveGovernedRegistry.Unauthorized();
        }
        _;
    }

    /// @inheritdoc IHyperdriveGovernedRegistry
    function updateAdmin(address _admin) external override onlyAdmin {
        admin = _admin;
        emit AdminUpdated(_admin);
    }

    /// @inheritdoc IHyperdriveGovernedRegistry
    function setFactoryInfo(
        address[] calldata _factories,
        uint128[] calldata _data
    ) external override onlyAdmin {
        // Ensure that the arrays have the same length.
        if (_factories.length != _data.length) {
            revert IHyperdriveGovernedRegistry.InputLengthMismatch();
        }

        // Add the Hyperdrive factory data to the registry.
        for (uint256 i = 0; i < _factories.length; i++) {
            // If the updated data is zero, we are deleting the entry. We remove
            // the entry from the list of Hyperdrive factories and delete the
            // stored info. If the existing data is zero, we can simply skip
            // this entry.
            uint256 data = _factoryInfo[_factories[i]].data;
            if (_data[i] == 0 && data != 0) {
                _removeFactoryInstance(_factories[i]);
            }
            // If the updated data is non-zero and the existing data is non-zero,
            // we are updating an existing entry in the registry.
            else if (_data[i] != 0 && data != 0) {
                _updateFactoryInstance(_factories[i], _data[i]);
            }
            // If the updated data is non-zero and the existing data is zero,
            // we are adding a new entry to the registry.
            else if (_data[i] != 0 && data == 0) {
                _addFactoryInstance(_factories[i], _data[i]);
            }

            // Emit an event recording the update.
            emit FactoryInfoUpdated(_factories[i], _data[i]);
        }
    }

    /// @inheritdoc IHyperdriveGovernedRegistry
    function setHyperdriveInfo(
        address[] calldata _instances,
        uint128[] calldata _data,
        address[] calldata _factories
    ) external override onlyAdmin {
        // Ensure that the arrays have the same length.
        if (
            _instances.length != _data.length ||
            _instances.length != _factories.length
        ) {
            revert IHyperdriveGovernedRegistry.InputLengthMismatch();
        }

        // Add the Hyperdrive data to the registry.
        for (uint256 i = 0; i < _instances.length; i++) {
            // If the updated data is zero, we are deleting the entry. The
            // factory should also be zero, and we remove the entry from the
            // list of Hyperdrive instances and delete the stored info. If the
            // existing data is zero, we can simply skip this entry.
            uint256 data = _hyperdriveInfo[_instances[i]].data;
            if (_data[i] == 0 && data != 0) {
                // Ensure that the factory address is zero.
                if (_factories[i] != address(0)) {
                    revert IHyperdriveGovernedRegistry.InvalidFactory();
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
            // Otherwise, the update is attempting to remove a non-existant
            // entry. To avoid emitting a confusing event, we continue.
            else {
                continue;
            }

            // Emit an event recording the update.
            emit HyperdriveInfoUpdated(_instances[i], _data[i], _factories[i]);
        }
    }

    /// @inheritdoc IHyperdriveRegistry
    function getNumberOfFactories() external view returns (uint256) {
        return _hyperdriveFactories.length;
    }

    /// @inheritdoc IHyperdriveRegistry
    function getFactoriesInRange(
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (address[] memory factories) {
        // If the indexes are malformed, revert.
        if (_startIndex > _endIndex) {
            revert IHyperdriveGovernedRegistry.InvalidIndexes();
        }
        if (_endIndex >= _hyperdriveInstances.length) {
            revert IHyperdriveGovernedRegistry.EndIndexTooLarge();
        }

        // Get the registered factories in the range.
        factories = new address[](_endIndex - _startIndex);
        for (uint256 i = _startIndex; i < _endIndex; i++) {
            factories[i] = _hyperdriveFactories[i];
        }

        return factories;
    }

    /// @inheritdoc IHyperdriveRegistry
    function getFactoryAtIndex(uint256 _index) external view returns (address) {
        return _hyperdriveFactories[_index];
    }

    /// @inheritdoc IHyperdriveRegistry
    function getFactoryInfo(
        address[] calldata _factories
    ) external view override returns (FactoryInfo[] memory info) {
        info = new FactoryInfo[](_factories.length);
        for (uint256 i = 0; i < _factories.length; i++) {
            info[i] = FactoryInfo({ data: _factoryInfo[_factories[i]].data });
        }
        return info;
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
        if (_startIndex > _endIndex) {
            revert IHyperdriveGovernedRegistry.InvalidIndexes();
        }
        if (_endIndex >= _hyperdriveInstances.length) {
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
    function getHyperdriveInstanceAtIndex(
        uint256 _index
    ) external view returns (address) {
        return _hyperdriveInstances[_index];
    }

    /// @inheritdoc IHyperdriveRegistry
    function getHyperdriveInfo(
        address[] calldata _instances
    ) external view override returns (HyperdriveInfo[] memory info) {
        info = new HyperdriveInfo[](_instances.length);
        for (uint256 i = 0; i < _instances.length; i++) {
            info[i] = HyperdriveInfo({
                data: _hyperdriveInfo[_instances[i]].data,
                factory: _hyperdriveInfo[_instances[i]].factory
            });
        }
        return info;
    }

    /// @dev Adds a new Hyperdrive factory to the registry.
    /// @param _factory The factory to add.
    /// @param _data The data associated with the new factory.
    function _addFactoryInstance(address _factory, uint128 _data) internal {
        // Add the new factory to the list of Hyperdrive factories.
        uint256 index = _hyperdriveFactories.length;
        _hyperdriveFactories.push(_factory);

        // Add the entry to the mapping.
        _factoryInfo[_factory] = FactoryInfoInternal({
            data: _data,
            index: uint128(index)
        });
    }

    /// @dev Adds a new Hyperdrive factory to the registry or updates an
    ///      existing Hyperdrive factory in the registry.
    /// @param _factory The Hyperdrive factory to update.
    /// @param _data The data associated with the new factory.
    function _updateFactoryInstance(address _factory, uint128 _data) internal {
        _factoryInfo[_factory].data = _data;
    }

    /// @dev Removes a Hyperdrive factory from the registry.
    /// @param _factory The Hyperdrive factory to remove.
    function _removeFactoryInstance(address _factory) internal {
        // Delete the entry from the factories list.
        _hyperdriveFactories[
            _factoryInfo[_factory].index
        ] = _hyperdriveFactories[_hyperdriveFactories.length - 1];
        _hyperdriveFactories.pop();

        // Delete the entry from the mapping.
        delete _factoryInfo[_factory];
    }

    /// @dev Adds a new Hyperdrive instance to the registry.
    /// @param _instance The instance to add.
    /// @param _data The data associated with the new instance.
    /// @param _factory The factory that deployed the new instance.
    function _addHyperdriveInstance(
        address _instance,
        uint128 _data,
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
        _hyperdriveInstances.push(_instance);

        // Add the entry to the mapping.
        _hyperdriveInfo[_instance] = HyperdriveInfoInternal({
            data: _data,
            factory: _factory,
            index: uint128(index)
        });
    }

    /// @dev Adds a new Hyperdrive instance to the registry or updates an
    ///      existing Hyperdrive instance in the registry.
    /// @param _instance The Hyperdrive instance to update.
    /// @param _data The data associated with the new instance.
    /// @param _factory The factory that deployed the new instance.
    function _updateHyperdriveInstance(
        address _instance,
        uint128 _data,
        address _factory
    ) internal {
        // If the existing factory address is non-zero, we verify that
        // the updated factory address is the same. Otherwise, if the
        // updated factory address is non-zero, verify that the
        // Hyperdrive instance was actually deployed by the factory. If
        // the updated factory address is zero, we skip this check.
        address factory = _hyperdriveInfo[_instance].factory;
        if (
            (factory != address(0) && factory != _factory) ||
            (factory == address(0) &&
                _factory != address(0) &&
                !IHyperdriveFactory(_factory).isInstance(_instance))
        ) {
            revert IHyperdriveGovernedRegistry.InvalidFactory();
        }

        // Update the entry in the mapping.
        _hyperdriveInfo[_instance].data = _data;
        _hyperdriveInfo[_instance].factory = _factory;
    }

    /// @dev Removes a Hyperdrive instance from the registry.
    /// @param _instance The Hyperdrive instance to remove.
    function _removeHyperdriveInstance(address _instance) internal {
        // Delete the entry from the instances list. If the instance isn't the
        // last item in the list, the item is replaced with the last item in the
        // list.
        uint128 index = _hyperdriveInfo[_instance].index;
        uint256 length = _hyperdriveInstances.length;
        if (index != length - 1) {
            // Update the index of the entry that will replace the removed entry
            // in the list.
            address replacementInstance = _hyperdriveInstances[length - 1];
            _hyperdriveInfo[replacementInstance].index = index;

            // Replace the entry that is being removed.
            _hyperdriveInstances[index] = replacementInstance;
        }
        _hyperdriveInstances.pop();

        // Delete the entry from the mapping.
        delete _hyperdriveInfo[_instance];
    }
}
