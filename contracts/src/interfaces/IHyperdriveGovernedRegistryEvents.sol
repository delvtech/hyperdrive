// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IHyperdriveGovernedRegistryEvents {
    /// @notice Emitted when the registry is initialized.
    event Initialized(string indexed name, address indexed admin);

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

    /// @notice Emitted when the name is updated.
    event NameUpdated(string indexed name);
}
