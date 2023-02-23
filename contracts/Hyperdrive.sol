// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { HyperdriveBase } from "contracts/HyperdriveBase.sol";
import { HyperdriveLong } from "contracts/HyperdriveLong.sol";
import { HyperdriveLP } from "contracts/HyperdriveLP.sol";
import { HyperdriveShort } from "contracts/HyperdriveShort.sol";
import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "contracts/interfaces/IHyperdrive.sol";

/// @author Delve
/// @title Hyperdrive
/// @notice A fixed-rate AMM that mints bonds on demand for longs and shorts.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract Hyperdrive is
    HyperdriveBase,
    HyperdriveLong,
    HyperdriveShort,
    HyperdriveLP
{
    using FixedPointMath for uint256;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @param _baseToken The base token contract.
    /// @param _initialSharePrice The initial share price.
    /// @param _checkpointsPerTerm The number of checkpoints that elaspes before
    ///        bonds can be redeemed one-to-one for base.
    /// @param _checkpointDuration The time in seconds between share price
    ///        checkpoints. Position duration must be a multiple of checkpoint
    ///        duration.
    /// @param _timeStretch The time stretch of the pool.
    /// @param _curveFee The fee parameter for the curve portion of the hyperdrive trade equation.
    /// @param _flatFee The fee parameter for the flat portion of the hyperdrive trade equation.
    constructor(
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _baseToken,
        uint256 _initialSharePrice,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        uint256 _curveFee,
        uint256 _flatFee
    )
        HyperdriveBase(
            _linkerCodeHash,
            _linkerFactory,
            _baseToken,
            _initialSharePrice,
            _checkpointsPerTerm,
            _checkpointDuration,
            _timeStretch,
            _curveFee,
            _flatFee
        )
    {}

    /// @notice Allows anyone to mint a new checkpoint.
    /// @param _checkpointTime The time of the checkpoint to create.
    function checkpoint(uint256 _checkpointTime) public override {
        // If the checkpoint has already been set, return early.
        if (checkpoints[_checkpointTime] != 0) {
            return;
        }

        // If the checkpoint time isn't divisible by the checkpoint duration
        // or is in the future, it's an invalid checkpoint and we should
        // revert.
        uint256 latestCheckpoint = _latestCheckpoint();
        if (
            _checkpointTime % checkpointDuration != 0 ||
            latestCheckpoint < _checkpointTime
        ) {
            revert Errors.InvalidCheckpointTime();
        }

        // If the checkpoint time is the latest checkpoint, we use the current
        // share price. Otherwise, we use a linear search to find the closest
        // share price and use that to perform the checkpoint.
        if (_checkpointTime == latestCheckpoint) {
            _applyCheckpoint(latestCheckpoint, pricePerShare());
        } else {
            for (uint256 time = _checkpointTime; ; time += checkpointDuration) {
                uint256 closestSharePrice = checkpoints[time];
                if (time == latestCheckpoint) {
                    closestSharePrice = pricePerShare();
                }
                if (closestSharePrice != 0) {
                    _applyCheckpoint(_checkpointTime, closestSharePrice);
                }
            }
        }
    }

    // TODO: If we find that this checkpointing flow is too heavy (which is
    // quite possible), we can store the share price and update some key metrics
    // about matured positions and add a poking system that performs the rest of
    // the computation.
    //
    /// @dev Creates a new checkpoint if necessary.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _sharePrice The current share price.
    /// @return openSharePrice The open share price of the latest checkpoint.
    function _applyCheckpoint(
        uint256 _checkpointTime,
        uint256 _sharePrice
    ) internal override returns (uint256 openSharePrice) {
        // Return early if the checkpoint has already been updated.
        if (
            checkpoints[_checkpointTime] != 0 ||
            _checkpointTime > block.timestamp
        ) {
            return checkpoints[_checkpointTime];
        }

        // Create the share price checkpoint.
        checkpoints[_checkpointTime] = _sharePrice;

        // Pay out the long withdrawal pool for longs that have matured.
        uint256 maturedLongsAmount = totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _checkpointTime)
        ];
        if (maturedLongsAmount > 0) {
            _applyCloseLong(
                maturedLongsAmount,
                0,
                maturedLongsAmount.divDown(_sharePrice),
                _sharePrice,
                _checkpointTime
            );
        }

        // Pay out the short withdrawal pool for shorts that have matured.
        uint256 maturedShortsAmount = totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _checkpointTime)
        ];
        if (maturedShortsAmount > 0) {
            _applyCloseShort(
                maturedShortsAmount,
                0,
                maturedShortsAmount.divDown(_sharePrice),
                _checkpointTime
            );
        }

        return checkpoints[_checkpointTime];
    }
}
