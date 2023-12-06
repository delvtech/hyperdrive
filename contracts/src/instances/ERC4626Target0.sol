// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveTarget0 } from "../external/HyperdriveTarget0.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { ERC4626Base } from "./ERC4626Base.sol";

/// @author DELV
/// @title ERC4626Target0
/// @notice ERC4626Hyperdrive's target 0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Target0 is HyperdriveTarget0, ERC4626Base {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __pool The ERC4626 pool.
    constructor(
        IHyperdrive.PoolDeployConfig memory _config,
        IERC4626 __pool
    ) HyperdriveTarget0(_config) ERC4626Base(__pool) {}

    /// Getters ///

    /// @notice Gets the 4626 pool.
    /// @return The 4626 pool.
    function pool() external view returns (IERC4626) {
        _revert(abi.encode(_pool));
    }

    /// @notice Gets the sweepable status of a target.
    /// @param _target The target address.
    function isSweepable(address _target) external view returns (bool) {
        _revert(abi.encode(_isSweepable[_target]));
    }
}
