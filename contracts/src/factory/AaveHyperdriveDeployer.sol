// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AaveHyperdrive } from "../instances/AaveHyperdrive.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { IPool } from "@aave/interfaces/IPool.sol";

interface IAToken {
    // solhint-disable-next-line func-name-mixedcase
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

/// @author DELV
/// @title AaveHyperdriveDeployer
/// @notice This is a minimal factory which contains only the logic to deploy hyperdrive
///                and is called by a more complex factory which also initializes hyperdrives.
/// @dev We use two contracts to avoid any code size limit issues with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract AaveHyperdriveDeployer is IHyperdriveDeployer {
    IPool internal immutable pool;

    constructor(IPool _pool) {
        pool = _pool;
    }

    /// @notice Deploys a copy of hyperdrive with the given params. NOTE -
    ///         This function varies from interface by requring aToken in the baseToken
    ///         field.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @param _baseToken The a token of the aave pool
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
        IERC20 _baseToken,
        uint256,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        IHyperdrive.Fees memory _fees,
        address _governance,
        bytes32[] calldata _extraData
    ) external override returns (address) {
        // We force convert
        bytes32 loaded = _extraData[0];
        IERC20 aToken;
        assembly ("memory-safe") {
            aToken := loaded
        }
        // Need a hard convert cause no direct bytes32 -> address
        return (
            address(
                new AaveHyperdrive(
                    _linkerCodeHash,
                    _linkerFactory,
                    _baseToken,
                    _checkpointsPerTerm,
                    _checkpointDuration,
                    _timeStretch,
                    aToken,
                    pool,
                    _fees,
                    _governance
                )
            )
        );
    }
}
