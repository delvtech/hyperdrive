// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveCoreDeployer } from "../../interfaces/IHyperdriveCoreDeployer.sol";
import { ILido } from "../../interfaces/ILido.sol";
import { StETHHyperdrive } from "../../instances/steth/StETHHyperdrive.sol";

/// @author DELV
/// @title StETHHyperdriveCoreDeployer
/// @notice The core deployer for the StETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StETHHyperdriveCoreDeployer is IHyperdriveCoreDeployer {
    /// @notice The Lido contract.
    ILido public immutable lido;

    /// @notice Instanstiates the core deployer.
    /// @param _lido The Lido contract.
    constructor(ILido _lido) {
        lido = _lido;
    }

    /// @notice Deploys a Hyperdrive instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param target0 The target0 address.
    /// @param target1 The target1 address.
    /// @param target2 The target2 address.
    /// @param target3 The target3 address.
    /// @return The address of the newly deployed StETHHyperdrive Instance.
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory, // unused extra data
        address target0,
        address target1,
        address target2,
        address target3
    ) external override returns (address) {
        return (
            address(
                new StETHHyperdrive(
                    _config,
                    target0,
                    target1,
                    target2,
                    target3,
                    lido
                )
            )
        );
    }
}
