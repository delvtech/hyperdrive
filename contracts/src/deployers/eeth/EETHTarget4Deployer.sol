// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { EETHTarget4 } from "../../instances/eeth/EETHTarget4.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { ILiquidityPool } from "../../interfaces/ILiquidityPool.sol";

/// @author DELV
/// @title EETHTarget4Deployer
/// @notice The target4 deployer for the EETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EETHTarget4Deployer is IHyperdriveTargetDeployer {
    /// @notice The Etherfi contract.
    ILiquidityPool public immutable liquidityPool;

    /// @notice Instantiates the core deployer.
    /// @param _liquidityPool The Etherfi contract.
    constructor(ILiquidityPool _liquidityPool) {
        liquidityPool = _liquidityPool;
    }

    /// @notice Deploys a target4 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed EETHTarget4 instance.
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
                new EETHTarget4{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, _adminController, liquidityPool)
            );
    }
}
