// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { SavingsUSDSL2Target0 } from "../../instances/savings-usds-l2/SavingsUSDSL2Target0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { IPSM } from "../../interfaces/IPSM.sol";

/// @author DELV
/// @title SavingsUSDSL2Target0Deployer
/// @notice The target0 deployer for the SavingsUSDSL2Hyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract SavingsUSDSL2Target0Deployer is IHyperdriveTargetDeployer {
    /// @notice Deploys a target0 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed SavingsUSDSL2Target0 instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController _adminController,
        bytes memory _extraData,
        bytes32 _salt
    ) external returns (address) {
        // The PSM contract. This is where the base token will be swapped
        // for shares.
        require(_extraData.length >= 20, "Invalid _extraData length");
        IPSM PSM = abi.decode(_extraData, (IPSM));

        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new SavingsUSDSL2Target0{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, _adminController, PSM)
            );
    }
}
