// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { MorphoBlueTarget4 } from "../../instances/morpho-blue/MorphoBlueTarget4.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { IMorphoBlueHyperdrive } from "../../interfaces/IMorphoBlueHyperdrive.sol";

/// @author DELV
/// @title MorphoBlueTarget4Deployer
/// @notice The target4 deployer for the MorphoBlueHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MorphoBlueTarget4Deployer is IHyperdriveTargetDeployer {
    /// @notice Deploys a target4 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _extraData The extra data for the Morpho instance. This contains
    ///        the market parameters that weren't specified in the config.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed MorphoBlueTarget4 instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController _adminController,
        bytes memory _extraData,
        bytes32 _salt
    ) external returns (address) {
        IMorphoBlueHyperdrive.MorphoBlueParams memory params = abi.decode(
            _extraData,
            (IMorphoBlueHyperdrive.MorphoBlueParams)
        );
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new MorphoBlueTarget4{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, _adminController, params)
            );
    }
}
