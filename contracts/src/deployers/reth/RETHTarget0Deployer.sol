// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { RETHTarget0 } from "../../instances/reth/RETHTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { IRocketStorage } from "../../interfaces/IRocketStorage.sol";

/// @author DELV
/// @title RETHTarget0Deployer
/// @notice The target0 deployer for the RETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract RETHTarget0Deployer is IHyperdriveTargetDeployer {
    /// @notice The Rocket Storage contract.
    IRocketStorage public immutable rocketStorage;

    /// @notice Instantiates the target0 deployer.
    /// @param _rocketStorage The Rocket Storage contract.
    constructor(IRocketStorage _rocketStorage) {
        rocketStorage = _rocketStorage;
    }

    /// @notice Deploys a target0 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed RETHTarget0 instance.
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory, // unused extra data
        bytes32 _salt
    ) external override returns (address) {
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new RETHTarget0{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, rocketStorage)
            );
    }
}
