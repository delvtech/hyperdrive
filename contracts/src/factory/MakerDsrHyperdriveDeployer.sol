// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MakerDsrHyperdrive } from "../instances/MakerDsrHyperdrive.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { DsrManager } from "../interfaces/IMaker.sol";

/// @author DELV
/// @title MakerDsrHyperdriveFactory
/// @notice This is a minimal factory which contains only the logic to deploy hyperdrive
///                 and is called by a more complex factory which also initializes hyperdrives.
/// @dev We use two contracts to avoid any code size limit issues with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MakerDsrHyperdriveDeployer is IHyperdriveDeployer {
    DsrManager internal immutable dsrManager;

    constructor(DsrManager _dsrManager) {
        dsrManager = _dsrManager;
    }

    /// @notice Deploys a copy of hyperdrive with the given params
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @param _checkpointsPerTerm The number of checkpoints that elapses before
    ///        bonds can be redeemed one-to-one for base.
    /// @param _checkpointDuration The time in seconds between share price
    ///        checkpoints. Position duration must be a multiple of checkpoint
    ///        duration.
    /// @param _timeStretch The time stretch of the pool.
    /// @param _fees The fees to apply to trades.
    /// @param _governance The address of the governance contract.
    function deploy(
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20,
        uint256,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        IHyperdrive.Fees memory _fees,
        address _governance,
        bytes32[] calldata
    ) external override returns (address) {
        return (
            address(
                new MakerDsrHyperdrive(
                    _linkerCodeHash,
                    _linkerFactory,
                    _checkpointsPerTerm,
                    _checkpointDuration,
                    _timeStretch,
                    _fees,
                    _governance,
                    dsrManager
                )
            )
        );
    }
}
