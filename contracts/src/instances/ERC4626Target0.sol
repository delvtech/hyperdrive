// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveTarget0 } from "../external/HyperdriveTarget0.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { ERC4626Base } from "./ERC4626Base.sol";

/// @author DELV
/// @title ERC4626DataProvider
/// @notice ERC4626Hyperdrive's target 0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Target0 is HyperdriveTarget0, ERC4626Base {
    // FIXME: Fix this Natspec.
    //
    /// @notice Initializes the logic contract.
    /// @param _linkerCodeHash_ The hash of the erc20 linker contract deploy code
    /// @param _factory_ The factory which is used to deploy the linking contracts
    /// @param _pool_ The ERC4626 pool.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash_,
        address _factory_,
        IERC4626 _pool_
    )
        HyperdriveTarget0(_config, _linkerCodeHash_, _factory_)
        ERC4626Base(_pool_)
    {}

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
