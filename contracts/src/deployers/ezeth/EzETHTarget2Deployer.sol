// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { EzETHTarget2 } from "../../instances/ezeth/EzETHTarget2.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { IRestakeManager } from "../../interfaces/IRenzo.sol";

/// @author DELV
/// @title EzETHTarget2Deployer
/// @notice The target2 deployer for the EzETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EzETHTarget2Deployer is IHyperdriveTargetDeployer {
    /// @notice The Renzo contract.
    IRestakeManager public immutable restakeManager;

    /// @notice Instantiates the core deployer.
    /// @param _restakeManager The Renzo contract.
    constructor(IRestakeManager _restakeManager) {
        restakeManager = _restakeManager;
    }

    /// @notice Deploys a target2 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed EzETHTarget2 instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController _adminController,
        bytes memory, // unused extra data
        bytes32 _salt
    ) external returns (address) {
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new EzETHTarget2{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, _adminController, restakeManager)
            );
    }
}
