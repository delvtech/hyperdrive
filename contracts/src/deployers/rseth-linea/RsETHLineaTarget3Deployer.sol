// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { RsETHLineaTarget3 } from "../../instances/rseth-linea/RsETHLineaTarget3.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { IRSETHPoolV2 } from "../../interfaces/IRSETHPoolV2.sol";

/// @author DELV
/// @title RsETHLineaTarget3Deployer
/// @notice The target3 deployer for the RsETHLineaHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract RsETHLineaTarget3Deployer is IHyperdriveTargetDeployer {
    /// @notice The Kelp DAO deposit contract on Linea. The rsETH/ETH price is
    ///         used as the vault share price.
    IRSETHPoolV2 public immutable rsETHPool;

    /// @notice Instantiates the rsETH Linea Hyperdrive base contract.
    /// @param _rsETHPool The Kelp DAO deposit contract that provides the vault
    ///        share price.
    constructor(IRSETHPoolV2 _rsETHPool) {
        rsETHPool = _rsETHPool;
    }

    /// @notice Deploys a target3 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed RsETHLineaTarget3 instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController _adminController,
        bytes memory, // unused  _extraData
        bytes32 _salt
    ) external returns (address) {
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new RsETHLineaTarget3{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, _adminController, rsETHPool)
            );
    }
}
