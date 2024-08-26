// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { RsETHLineaTarget3 } from "../../instances/rseth-linea/RsETHLineaTarget3.sol";
import { IRsETHLinea } from "../../interfaces/IRsETHLinea.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";

/// @author DELV
/// @title RsETHLineaTarget3Deployer
/// @notice The target3 deployer for the RsETHLineaHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract RsETHLineaTarget3Deployer is IHyperdriveTargetDeployer {
    /// @notice Deploys a target3 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed RsETHLineaTarget3 instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        bytes memory, // unused  _extraData
        bytes32 _salt
    ) external returns (address) {
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new RsETHLineaTarget3{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config)
            );
    }
}
