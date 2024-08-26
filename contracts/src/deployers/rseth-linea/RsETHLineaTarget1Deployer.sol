// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { RsETHLineaTarget1 } from "../../instances/rseth-linea/RsETHLineaTarget1.sol";
import { IRsETHLinea } from "../../interfaces/IRsETHLinea.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";

/// @author DELV
/// @title RsETHLineaTarget1Deployer
/// @notice The target1 deployer for the RsETHLineaHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract RsETHLineaTarget1Deployer is IHyperdriveTargetDeployer {
    /// @notice Deploys a target1 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed RsETHLineaTarget1 instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        bytes memory, // unused _extraData
        bytes32 _salt
    ) external returns (address) {
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new RsETHLineaTarget1{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config)
            );
    }
}
