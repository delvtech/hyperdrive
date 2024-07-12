// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { MorphoBlueTarget1 } from "../../instances/morpho-blue/MorphoBlueTarget1.sol";
import { IMorphoBlue } from "../../interfaces/IMorphoBlue.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";

/// @author DELV
/// @title MorphoBlueTarget1Deployer
/// @notice The target1 deployer for the MorphoBlueHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MorphoBlueTarget1Deployer is IHyperdriveTargetDeployer {
    /// @notice Deploys a target1 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed MorphoBlueTarget1 instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        bytes memory, // unused _extraData
        bytes32 _salt
    ) external returns (address) {
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new MorphoBlueTarget1{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config)
            );
    }
}
