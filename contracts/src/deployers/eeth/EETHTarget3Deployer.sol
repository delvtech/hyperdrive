// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { EETHTarget3 } from "../../instances/eeth/EETHTarget3.sol";
import { IeETH } from "etherfi/src/interfaces/IeETH.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { ILiquidityPool } from "etherfi/src/interfaces/ILiquidityPool.sol";

/// @author DELV
/// @title EETHTarget3Deployer
/// @notice The target3 deployer for the EETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EETHTarget3Deployer is IHyperdriveTargetDeployer {
    /// @notice The Etherfi contract.
    ILiquidityPool public immutable liquidityPool;

    /// @notice Instantiates the core deployer.
    /// @param _liquidityPool The Etherfi contract.
    constructor(ILiquidityPool _liquidityPool) {
        liquidityPool = _liquidityPool;
    }

    /// @notice Deploys a target3 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed EETHTarget3 instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        bytes memory, // unused  _extraData
        bytes32 _salt
    ) external returns (address) {
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new EETHTarget3{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, liquidityPool)
            );
    }
}
