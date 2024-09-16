// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { CornTarget1 } from "../../instances/corn/CornTarget1.sol";
import { ICornSilo } from "../../interfaces/ICornSilo.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";

/// @author DELV
/// @title CornTarget1Deployer
/// @notice The target1 deployer for the CornHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract CornTarget1Deployer is IHyperdriveTargetDeployer {
    /// @dev The Corn Silo contract. This is where the base token will be
    ///      deposited.
    ICornSilo internal immutable cornSilo;

    /// @notice Instantiates the CornHyperdrive base contract.
    /// @param _cornSilo The Corn Silo contract.
    constructor(ICornSilo _cornSilo) {
        cornSilo = _cornSilo;
    }

    /// @notice Deploys a target1 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed CornTarget1 instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController _adminController,
        bytes memory, // unused _extraData
        bytes32 _salt
    ) external returns (address) {
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new CornTarget1{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, _adminController, cornSilo)
            );
    }
}
