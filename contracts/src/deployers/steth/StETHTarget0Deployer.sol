// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { StETHTarget0 } from "../../instances/steth/StETHTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { ILido } from "../../interfaces/ILido.sol";

/// @author DELV
/// @title StETHTarget0Deployer
/// @notice The target0 deployer for the StETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StETHTarget0Deployer is IHyperdriveTargetDeployer {
    /// @notice Deploys a target0 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains the pool and sweep targets.
    /// @return The address of the newly deployed StETHTarget0 Instance.
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory _extraData
    ) external override returns (address) {
        // Deploy the StETHTarget0 instance.
        ILido lido = ILido(abi.decode(_extraData, (address)));
        return address(new StETHTarget0(_config, lido));
    }
}
