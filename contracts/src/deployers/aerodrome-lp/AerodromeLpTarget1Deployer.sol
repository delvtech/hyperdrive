// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IGauge } from "aerodrome/interfaces/IGauge.sol";
import { AerodromeLpTarget1 } from "../../instances/aerodrome-lp/AerodromeLpTarget1.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";

/// @author DELV
/// @title AerodromeLpTarget1Deployer
/// @notice The target1 deployer for the AerodromeLpHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract AerodromeLpTarget1Deployer is IHyperdriveTargetDeployer {
    /// @notice Deploys a target1 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed AerodromeLpTarget1 instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController _adminController,
        bytes memory _extraData,
        bytes32 _salt
    ) external returns (address) {
        // The Aerodrome Gauge contract. This is where the base token will be
        // deposited.
        require(_extraData.length >= 20, "Invalid _extraData length");
        IGauge gauge = abi.decode(_extraData, (IGauge));

        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new AerodromeLpTarget1{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, _adminController, gauge)
            );
    }
}
