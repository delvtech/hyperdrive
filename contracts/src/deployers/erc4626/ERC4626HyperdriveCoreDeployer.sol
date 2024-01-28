// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveCoreDeployer } from "../../interfaces/IHyperdriveCoreDeployer.sol";
import { ERC4626Hyperdrive } from "../../instances/erc4626/ERC4626Hyperdrive.sol";

/// @author DELV
/// @title ERC4626HyperdriveCoreDeployer
/// @notice The core deployer for the ERC4626Hyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626HyperdriveCoreDeployer is IHyperdriveCoreDeployer {
    /// @notice Deploys a Hyperdrive instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains the ERC4626 vault.
    /// @param target0 The target0 address.
    /// @param target1 The target1 address.
    /// @param target2 The target2 address.
    /// @param target3 The target3 address.
    /// @param target4 The target4 address.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed ERC4626Hyperdrive instance.
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory _extraData,
        address target0,
        address target1,
        address target2,
        address target3,
        address target4,
        bytes32 _salt
    ) external returns (address) {
        address vault = abi.decode(_extraData, (address));
        return (
            address(
                new ERC4626Hyperdrive{ salt: _salt }(
                    _config,
                    target0,
                    target1,
                    target2,
                    target3,
                    target4,
                    IERC4626(vault)
                )
            )
        );
    }
}
