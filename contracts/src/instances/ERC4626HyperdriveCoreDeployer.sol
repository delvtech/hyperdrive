// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IERC4626HyperdriveDeployer } from "../interfaces/IERC4626HyperdriveDeployer.sol";
import { ERC4626Hyperdrive } from "../instances/ERC4626Hyperdrive.sol";

/// @author DELV
/// @title ERC4626HyperdriveCoreDeployer
/// @notice This is a minimal factory which contains only the logic to deploy
///         the hyperdrive contract and is called by a more complex factory which
///         initializes the Hyperdrive instances and acts as a registry.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626HyperdriveCoreDeployer is IERC4626HyperdriveDeployer {
    /// @notice Deploys a Hyperdrive instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains the sweep targets.
    /// @param target0 The address of the first target contract.
    /// @param target1 The address of the second target contract.
    /// @return The address of the newly deployed ERC4626Hyperdrive Instance
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory _extraData,
        address target0,
        address target1
    ) external override returns (address) {
        (address pool, address[] memory sweepTargets) = abi.decode(
            _extraData,
            (address, address[])
        );

        // Deploy the ERC4626Hyperdrive instance.
        return (
            address(
                new ERC4626Hyperdrive(
                    _config,
                    target0,
                    target1,
                    IERC4626(pool),
                    sweepTargets
                )
            )
        );
    }
}
