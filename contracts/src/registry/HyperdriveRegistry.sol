// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveFactory } from "../interfaces/IHyperdriveFactory.sol";
import { IHyperdriveGovernedRegistry } from "../interfaces/IHyperdriveGovernedRegistry.sol";
import { IHyperdriveRegistry } from "../interfaces/IHyperdriveRegistry.sol";
import { HYPERDRIVE_REGISTRY_KIND, VERSION } from "../libraries/Constants.sol";
import { SafeCast } from "../libraries/SafeCast.sol";

/// @author DELV
/// @title HyperdriveRegistry
/// @notice Allows an admin address to manage a list of registered Hyperdrive
///         instances and factories. This provides a convenient place for
///         consumers of Hyperdrive contracts to query a list of well-known
///         pools.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveRegistry is
    IHyperdriveRegistry,
    IHyperdriveGovernedRegistry
{
    using SafeCast for *;

    /// @notice Indicates whether or not the registry is initialized.
    bool public isInitialized;

    /// @notice The registry's name.
    string public name;

    /// @notice The registry's kind.
    string public constant kind = HYPERDRIVE_REGISTRY_KIND;

    /// @notice The registry's version.
    string public constant version = VERSION;

    /// @notice The registry's admin address.
    address public admin;

    /// @dev A list of all of the Hyperdrive factories that have been added to
    ///      the Hyperdrive registry.
    address[] internal _factories;

    /// @dev A mapping from hyperdrive factories to info associated with those
    ///      factories.
    mapping(address factory => FactoryInfoInternal info) internal _factoryInfo;

    /// @dev A list of all of the Hyperdrive instances that have been added to
    ///      the Hyperdrive registry.
    address[] internal _instances;

    /// @dev A mapping from hyperdrive instances to info associated with those
    ///      instances.
    mapping(address hyperdrive => InstanceInfoInternal info)
        internal _instanceInfo;

    /// @dev Ensures that the modified function is only called by the admin.
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert IHyperdriveGovernedRegistry.Unauthorized();
        }
        _;
    }

    /// @inheritdoc IHyperdriveGovernedRegistry
    function initialize(string calldata _name, address _admin) external {
        // Ensure that the registry hasn't already been initialized.
        if (isInitialized) {
            revert IHyperdriveGovernedRegistry.RegistryAlreadyInitialized();
        }

        // Set the initialization flag, name, and admin.
        isInitialized = true;
        name = _name;
        admin = _admin;

        // Emit an event.
        emit Initialized(_name, _admin);
    }

    /// @inheritdoc IHyperdriveGovernedRegistry
    function updateAdmin(address _admin) external onlyAdmin {
        admin = _admin;
        emit AdminUpdated(_admin);
    }

    /// @inheritdoc IHyperdriveGovernedRegistry
    function updateName(string memory _name) external onlyAdmin {
        name = _name;
        emit NameUpdated(_name);
    }

    /// @inheritdoc IHyperdriveGovernedRegistry
    function setFactoryInfo(
        address[] calldata __factories,
        uint128[] calldata _data
    ) external override onlyAdmin {
        // Ensure that the arrays have the same length.
        if (__factories.length != _data.length) {
            revert IHyperdriveGovernedRegistry.InputLengthMismatch();
        }

        // Add the Hyperdrive factory data to the registry.
        for (uint256 i = 0; i < __factories.length; i++) {
            // If the updated data is zero, we are deleting the entry. We remove
            // the entry from the list of Hyperdrive factories and delete the
            // stored info. If the existing data is zero, we can simply skip
            // this entry.
            uint256 data = _factoryInfo[__factories[i]].data;
            if (_data[i] == 0 && data != 0) {
                _removeFactory(__factories[i]);
            }
            // If the updated data is non-zero and the existing data is non-zero,
            // we are updating an existing entry in the registry.
            else if (_data[i] != 0 && data != 0) {
                _updateFactory(__factories[i], _data[i]);
            }
            // If the updated data is non-zero and the existing data is zero,
            // we are adding a new entry to the registry.
            else if (_data[i] != 0 && data == 0) {
                _addFactory(__factories[i], _data[i]);
            }
            // Otherwise, the update is attempting to remove a non-existant
            // entry. To avoid emitting a confusing event, we continue.
            else {
                continue;
            }

            // Emit an event recording the update.
            emit FactoryInfoUpdated(__factories[i], _data[i]);
        }
    }

    /// @inheritdoc IHyperdriveGovernedRegistry
    function setInstanceInfo(
        address[] calldata __instances,
        uint128[] calldata _data,
        address[] calldata __factories
    ) external override onlyAdmin {
        // Ensure that the arrays have the same length.
        if (
            __instances.length != _data.length ||
            __instances.length != __factories.length
        ) {
            revert IHyperdriveGovernedRegistry.InputLengthMismatch();
        }

        // Add the Hyperdrive data to the registry.
        for (uint256 i = 0; i < __instances.length; i++) {
            // If the updated data is zero, we are deleting the entry. The
            // factory should also be zero, and we remove the entry from the
            // list of Hyperdrive instances and delete the stored info. If the
            // existing data is zero, we can simply skip this entry.
            uint256 data = _instanceInfo[__instances[i]].data;
            if (_data[i] == 0 && data != 0) {
                // Ensure that the factory address is zero.
                if (__factories[i] != address(0)) {
                    revert IHyperdriveGovernedRegistry.InvalidFactory();
                }

                // Remove the entry from the registry.
                _removeInstance(__instances[i]);
            }
            // If the updated data is non-zero and the existing data is non-zero,
            // we are updating an existing entry in the registry.
            else if (_data[i] != 0 && data != 0) {
                _updateInstance(__instances[i], _data[i], __factories[i]);
            }
            // If the updated data is non-zero and the existing data is zero,
            // we are adding a new entry to the registry.
            else if (_data[i] != 0 && data == 0) {
                _addInstance(__instances[i], _data[i], __factories[i]);
            }
            // Otherwise, the update is attempting to remove a non-existant
            // entry. To avoid emitting a confusing event, we continue.
            else {
                continue;
            }

            // Emit an event recording the update.
            emit InstanceInfoUpdated(__instances[i], _data[i], __factories[i]);
        }
    }

    /// @inheritdoc IHyperdriveRegistry
    function getNumberOfFactories() external view returns (uint256) {
        return _factories.length;
    }

    /// @inheritdoc IHyperdriveRegistry
    function getFactoriesInRange(
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (address[] memory factories) {
        // If the indexes are malformed, revert.
        if (_startIndex >= _endIndex) {
            revert IHyperdriveGovernedRegistry.InvalidIndexes();
        }
        if (_endIndex > _factories.length) {
            revert IHyperdriveGovernedRegistry.EndIndexTooLarge();
        }

        // Get the registered factories in the range.
        factories = new address[](_endIndex - _startIndex);
        for (uint256 i = _startIndex; i < _endIndex; i++) {
            factories[i - _startIndex] = _factories[i];
        }

        return factories;
    }

    /// @inheritdoc IHyperdriveRegistry
    function getFactoryAtIndex(uint256 _index) external view returns (address) {
        return _factories[_index];
    }

    /// @inheritdoc IHyperdriveRegistry
    function getFactoryInfo(
        address _factory
    ) external view override returns (FactoryInfo memory info) {
        return FactoryInfo({ data: _factoryInfo[_factory].data });
    }

    /// @inheritdoc IHyperdriveRegistry
    function getFactoryInfos(
        address[] calldata __factories
    ) external view override returns (FactoryInfo[] memory info) {
        info = new FactoryInfo[](__factories.length);
        for (uint256 i = 0; i < __factories.length; i++) {
            info[i] = FactoryInfo({ data: _factoryInfo[__factories[i]].data });
        }
        return info;
    }

    /// @inheritdoc IHyperdriveRegistry
    function getFactoryInfoWithMetadata(
        address _factory
    ) external view override returns (FactoryInfoWithMetadata memory info) {
        IHyperdriveFactory factory = IHyperdriveFactory(_factory);
        return
            FactoryInfoWithMetadata({
                data: _factoryInfo[_factory].data,
                name: factory.name(),
                kind: factory.kind(),
                version: factory.version()
            });
    }

    /// @inheritdoc IHyperdriveRegistry
    function getFactoryInfosWithMetadata(
        address[] calldata __factories
    ) external view override returns (FactoryInfoWithMetadata[] memory info) {
        info = new FactoryInfoWithMetadata[](__factories.length);
        for (uint256 i = 0; i < __factories.length; i++) {
            IHyperdriveFactory factory = IHyperdriveFactory(__factories[i]);
            info[i] = FactoryInfoWithMetadata({
                data: _factoryInfo[__factories[i]].data,
                name: factory.name(),
                kind: factory.kind(),
                version: factory.version()
            });
        }
        return info;
    }

    /// @inheritdoc IHyperdriveRegistry
    function getNumberOfInstances() external view returns (uint256) {
        return _instances.length;
    }

    /// @inheritdoc IHyperdriveRegistry
    function getInstancesInRange(
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (address[] memory instances) {
        // If the indexes are malformed, revert.
        if (_startIndex >= _endIndex) {
            revert IHyperdriveGovernedRegistry.InvalidIndexes();
        }
        if (_endIndex > _instances.length) {
            revert IHyperdriveGovernedRegistry.EndIndexTooLarge();
        }

        // Get the registered instances in the range.
        instances = new address[](_endIndex - _startIndex);
        for (uint256 i = _startIndex; i < _endIndex; i++) {
            instances[i - _startIndex] = _instances[i];
        }

        return instances;
    }

    /// @inheritdoc IHyperdriveRegistry
    function getInstanceAtIndex(
        uint256 _index
    ) external view returns (address) {
        return _instances[_index];
    }

    /// @inheritdoc IHyperdriveRegistry
    function getInstanceInfo(
        address _instance
    ) external view override returns (InstanceInfo memory info) {
        return
            InstanceInfo({
                data: _instanceInfo[_instance].data,
                factory: _instanceInfo[_instance].factory
            });
    }

    /// @inheritdoc IHyperdriveRegistry
    function getInstanceInfos(
        address[] calldata __instances
    ) external view override returns (InstanceInfo[] memory info) {
        info = new InstanceInfo[](__instances.length);
        for (uint256 i = 0; i < __instances.length; i++) {
            info[i] = InstanceInfo({
                data: _instanceInfo[__instances[i]].data,
                factory: _instanceInfo[__instances[i]].factory
            });
        }
        return info;
    }

    /// @inheritdoc IHyperdriveRegistry
    function getInstanceInfoWithMetadata(
        address _instance
    ) external view override returns (InstanceInfoWithMetadata memory info) {
        IHyperdrive instance = IHyperdrive(_instance);
        return
            InstanceInfoWithMetadata({
                data: _instanceInfo[_instance].data,
                factory: _instanceInfo[_instance].factory,
                name: instance.name(),
                kind: instance.kind(),
                version: instance.version()
            });
    }

    /// @inheritdoc IHyperdriveRegistry
    function getInstanceInfosWithMetadata(
        address[] calldata __instances
    ) external view override returns (InstanceInfoWithMetadata[] memory info) {
        info = new InstanceInfoWithMetadata[](__instances.length);
        for (uint256 i = 0; i < __instances.length; i++) {
            IHyperdrive instance = IHyperdrive(__instances[i]);
            info[i] = InstanceInfoWithMetadata({
                data: _instanceInfo[__instances[i]].data,
                factory: _instanceInfo[__instances[i]].factory,
                name: instance.name(),
                kind: instance.kind(),
                version: instance.version()
            });
        }
        return info;
    }

    /// @dev Adds a new Hyperdrive factory to the registry.
    /// @param _factory The factory to add.
    /// @param _data The data associated with the new factory.
    function _addFactory(address _factory, uint128 _data) internal {
        // Add the new factory to the list of Hyperdrive factories.
        uint256 index = _factories.length;
        _factories.push(_factory);

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
    function _updateFactory(address _factory, uint128 _data) internal {
        _factoryInfo[_factory].data = _data;
    }

    /// @dev Removes a Hyperdrive factory from the registry.
    /// @param _factory The Hyperdrive factory to remove.
    function _removeFactory(address _factory) internal {
        // Delete the entry from the factories list. If the factory isn't the
        // last item in the list, the item is replaced with the last item in the
        // list.
        uint128 index = _factoryInfo[_factory].index;
        uint256 length = _factories.length;
        if (index != length - 1) {
            // Update the index of the entry that will replace the removed entry
            // in the list.
            address replacementFactory = _factories[length - 1];
            _factoryInfo[replacementFactory].index = index;

            // Replace the entry that is being removed.
            _factories[index] = replacementFactory;
        }
        _factories.pop();

        // Delete the entry from the mapping.
        delete _factoryInfo[_factory];
    }

    /// @dev Adds a new Hyperdrive instance to the registry.
    /// @param _instance The instance to add.
    /// @param _data The data associated with the new instance.
    /// @param _factory The factory that deployed the new instance.
    function _addInstance(
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
        uint256 index = _instances.length;
        _instances.push(_instance);

        // Add the entry to the mapping.
        _instanceInfo[_instance] = InstanceInfoInternal({
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
    function _updateInstance(
        address _instance,
        uint128 _data,
        address _factory
    ) internal {
        // If the existing factory address is non-zero, we verify that
        // the updated factory address is the same. Otherwise, if the
        // updated factory address is non-zero, verify that the
        // Hyperdrive instance was actually deployed by the factory. If
        // the updated factory address is zero, we skip this check.
        address factory = _instanceInfo[_instance].factory;
        if (
            (factory != address(0) && factory != _factory) ||
            (factory == address(0) &&
                _factory != address(0) &&
                !IHyperdriveFactory(_factory).isInstance(_instance))
        ) {
            revert IHyperdriveGovernedRegistry.InvalidFactory();
        }

        // Update the entry in the mapping.
        _instanceInfo[_instance].data = _data;
        _instanceInfo[_instance].factory = _factory;
    }

    /// @dev Removes a Hyperdrive instance from the registry.
    /// @param _instance The Hyperdrive instance to remove.
    function _removeInstance(address _instance) internal {
        // Delete the entry from the instances list. If the instance isn't the
        // last item in the list, the item is replaced with the last item in the
        // list.
        uint128 index = _instanceInfo[_instance].index;
        uint256 length = _instances.length;
        if (index != length - 1) {
            // Update the index of the entry that will replace the removed entry
            // in the list.
            address replacementInstance = _instances[length - 1];
            _instanceInfo[replacementInstance].index = index;

            // Replace the entry that is being removed.
            _instances[index] = replacementInstance;
        }
        _instances.pop();

        // Delete the entry from the mapping.
        delete _instanceInfo[_instance];
    }
}
