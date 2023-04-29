// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { MakerDsrHyperdrive } from "../instances/MakerDsrHyperdrive.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { DsrManager } from "../interfaces/IMaker.sol";

/// @author DELV
/// @title MakerDsrHyperdriveFactory
/// @notice This is a minimal factory which contains only the logic to deploy
///         hyperdrive and is called by a more complex factory which
///         initializes the Hyperdrive instances and acts as a registry.
/// @dev We use two contracts to avoid any code size limit issues with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MakerDsrHyperdriveDeployer is IHyperdriveDeployer {
    DsrManager internal immutable dsrManager;

    constructor(DsrManager _dsrManager) {
        dsrManager = _dsrManager;
    }

    /// @notice Deploys a copy of hyperdrive with the given params.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    function deploy(
        IHyperdrive.HyperdriveConfig memory _config,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        bytes32[] calldata
    ) external override returns (address) {
        return (
            address(
                new MakerDsrHyperdrive(
                    _config,
                    _linkerCodeHash,
                    _linkerFactory,
                    dsrManager
                )
            )
        );
    }
}
