// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { LsETHTarget1 } from "../../instances/lseth/LsETHTarget1.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { IRiverV1 } from "../../interfaces/lseth/IRiverV1.sol";

/// @author DELV
/// @title LsETHTarget1Deployer
/// @notice The target1 deployer for the LsETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract LsETHTarget1Deployer is IHyperdriveTargetDeployer {
    /// @dev The lsETH contract.
    IRiverV1 internal immutable _river;

    /// @notice Instantiates the target1 deployer.
    /// @param __river The lsETH contract.
    constructor(IRiverV1 __river) {
        _river = __river;
    }

    /// @notice Deploys a target1 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed LsETHTarget1 instance.
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory, // unused extra data
        bytes32 _salt
    ) external override returns (address) {
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new LsETHTarget1{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, _river)
            );
    }
}