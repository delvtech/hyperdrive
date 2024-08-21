// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveCoreDeployer } from "../../interfaces/IHyperdriveCoreDeployer.sol";
import { IRestakeManager } from "../../interfaces/IRenzo.sol";
import { EzETHHyperdrive } from "../../instances/ezeth/EzETHHyperdrive.sol";

/// @author DELV
/// @title EzETHHyperdriveCoreDeployer
/// @notice The core deployer for the EzETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EzETHHyperdriveCoreDeployer is IHyperdriveCoreDeployer {
    /// @notice The Renzo contract.
    IRestakeManager public immutable restakeManager;

    /// @notice Instantiates the core deployer.
    /// @param _restakeManager The Renzo contract.
    constructor(IRestakeManager _restakeManager) {
        restakeManager = _restakeManager;
    }

    /// @notice Deploys a Hyperdrive instance with the given parameters.
    /// @param __name The name of the Hyperdrive pool.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param target0 The target0 address.
    /// @param target1 The target1 address.
    /// @param target2 The target2 address.
    /// @param target3 The target3 address.
    /// @param target4 The target4 address.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed EzETHHyperdrive instance.
    function deployHyperdrive(
        string memory __name,
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController _adminController,
        bytes memory, // unused extra data
        address target0,
        address target1,
        address target2,
        address target3,
        address target4,
        bytes32 _salt
    ) external returns (address) {
        address hyperdrive = address(
            // NOTE: We hash the sender with the salt to prevent the
            // front-running of deployments.
            new EzETHHyperdrive{
                salt: keccak256(abi.encode(msg.sender, _salt))
            }(
                __name,
                _config,
                _adminController,
                target0,
                target1,
                target2,
                target3,
                target4,
                restakeManager
            )
        );
        return hyperdrive;
    }
}
