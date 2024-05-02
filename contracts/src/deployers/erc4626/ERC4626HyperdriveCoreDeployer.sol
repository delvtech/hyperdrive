// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

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
    /// @param _target0 The target0 address.
    /// @param _target1 The target1 address.
    /// @param _target2 The target2 address.
    /// @param _target3 The target3 address.
    /// @param _target4 The target4 address.
    /// @param _target5 The target5 address.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed ERC4626Hyperdrive instance.
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory, // unused extra data
        address _target0,
        address _target1,
        address _target2,
        address _target3,
        address _target4,
        address _target5,
        bytes32 _salt
    ) external returns (address) {
        address hyperdrive = address(
            // NOTE: We hash the sender with the salt to prevent the
            // front-running of deployments.
            new ERC4626Hyperdrive{
                salt: keccak256(abi.encode(msg.sender, _salt))
            }(
                _config,
                _target0,
                _target1,
                _target2,
                _target3,
                _target4,
                _target5
            )
        );
        return hyperdrive;
    }
}
