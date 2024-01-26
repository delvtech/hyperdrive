// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { StETHTarget2 } from "../../instances/steth/StETHTarget2.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { ILido } from "../../interfaces/ILido.sol";

/// @author DELV
/// @title StETHTarget2Deployer
/// @notice The target2 deployer for the StETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StETHTarget2Deployer is IHyperdriveTargetDeployer {
    /// @notice The Lido contract.
    ILido public immutable lido;

    /// @notice Instanstiates the target2 deployer.
    /// @param _lido The Lido contract.
    constructor(ILido _lido) {
        lido = _lido;
    }

    /// @notice Deploys a target2 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @return The address of the newly deployed StETHTarget2 Instance.
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory // unused extra data
    ) external override returns (address) {
        // Deploy the StETHTarget2 instance.
        return address(new StETHTarget2(_config, lido));
    }
}
