// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

interface IHyperdriveRegistry {
    /// @notice Emitted when governance is transferred.
    event GovernanceUpdated(address indexed governance);

    /// @notice Emitted when hyperdrive info is updated.
    event HyperdriveInfoUpdated(address indexed hyperdrive, bytes32 key, bytes32 data);

    /// @notice Struct to allow for arbitrary data to be stored for a hyperdrive instance by key.
    struct DataSlot {
        uint256 lastUpdated;
        bytes32 data;
    }
}
