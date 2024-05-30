// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC20 } from "./IERC20.sol";
import { IHyperdriveRegistry } from "./IHyperdriveRegistry.sol";

interface IHyperdriveGovernedRegistry is IHyperdriveRegistry {
    /// @notice Emitted when governance is transferred.
    event GovernanceUpdated(address indexed governance);

    /// @notice Emitted when hyperdrive info is updated.
    event HyperdriveInfoUpdated(
        address indexed hyperdrive,
        uint256 indexed data,
        uint256 indexed factory
    );

    /// @dev The info collected for each Hyperdrive instance.
    struct HyperdriveInfoInternal {
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

    /// @notice Thrown when caller is not governance.
    error Unauthorized();

    /// @notice Allows governance to transfer the governance role.
    /// @param _governance The new governance address.
    function updateGovernance(address _governance) external;

    /// @notice Allows governance to set arbitrary info for a Hyperdrive
    ///         instance.
    /// @param _hyperdriveInstance The Hyperdrive instance address.
    /// @param _data The uint256 value to be set to convey information about the
    ///        instance.
    function setHyperdriveInfo(
        address _hyperdriveInstance,
        uint256 _data
    ) external;
}
