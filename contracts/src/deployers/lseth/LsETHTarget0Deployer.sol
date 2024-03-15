// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { LsETHTarget0 } from "../../instances/lseth/LsETHTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { IRiverV1 } from "../../interfaces/lseth/IRiverV1.sol";

/// @author DELV
/// @title LsETHTarget0Deployer
/// @notice The target0 deployer for the LsETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract LsETHTarget0Deployer is IHyperdriveTargetDeployer {
    /// @dev The LsETH contract.
    IRiverV1 internal immutable _river;

    /// @notice Instantiates the target0 deployer.
    /// @param __river The lsETH contract.
    constructor(IRiverV1 __river) {
        _river = __river;
    }

    /// @notice Deploys a target0 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed LsETHTarget0 instance.
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory, // unused extra data
        bytes32 _salt
    ) external override returns (address) {
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new LsETHTarget0{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, _river)
            );
    }
}
