// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626Hyperdrive } from "../instances/ERC4626Hyperdrive.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";

/// @author DELV
/// @title ERC4626HyperdriveDeploer
/// @notice This is a minimal factory which contains only the logic to deploy
///         Hyperdrive and is called by a more complex factory which
///         initializes the Hyperdrive instances and acts as a registry.
/// @dev We use two contracts to avoid any code size limit issues with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626HyperdriveDeployer is IHyperdriveDeployer {
    IERC4626 internal immutable pool;

    /// @notice Instantiates the Hyperdrive deployer.
    /// @param _pool The address of the ERC4626 pool this deployer utilizes.
    constructor(IERC4626 _pool) {
        pool = _pool;
    }

    /// @notice Deploys a Hyperdrive instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _target0 The target0 address.
    /// @param _target1 The target1 address.
    /// @param _extraData The extra data that contains the sweep targets.
    /// @return The address of the newly deployed ERC4626Hyperdrive Instance
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        address _target0,
        address _target1,
        bytes32[] memory _extraData
    ) external override returns (address) {
        // Convert the extra data to an array of addresses.
        address[] memory sweepTargets;
        assembly ("memory-safe") {
            sweepTargets := _extraData
        }

        // Deploy the ERC4626Hyperdrive instance.
        return (
            address(
                new ERC4626Hyperdrive(
                    _config,
                    _target0,
                    _target1,
                    pool,
                    sweepTargets
                )
            )
        );
    }
}
