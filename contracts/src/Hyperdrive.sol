// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
import { HyperdriveLong } from "./HyperdriveLong.sol";
import { HyperdriveShort } from "./HyperdriveShort.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { Errors } from "./libraries/Errors.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";

/// @author DELV
/// @title Hyperdrive
/// @notice A fixed-rate AMM that mints bonds on demand for longs and shorts.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract Hyperdrive is
    HyperdriveBase,
    HyperdriveLong,
    HyperdriveShort
{
    using FixedPointMath for uint256;
    using SafeCast for uint256;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @param _baseToken The base token contract.
    /// @param _initialSharePrice The initial share price.
    /// @param _checkpointsPerTerm The number of checkpoints that elapses before
    ///        bonds can be redeemed one-to-one for base.
    /// @param _checkpointDuration The time in seconds between share price
    ///        checkpoints. Position duration must be a multiple of checkpoint
    ///        duration.
    /// @param _timeStretch The time stretch of the pool.
    /// @param _fees The fees to apply to trades.
    /// @param _governance The address of the governance contract.
    constructor(
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _baseToken,
        uint256 _initialSharePrice,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        IHyperdrive.Fees memory _fees,
        address _governance
    )
        HyperdriveBase(
            _linkerCodeHash,
            _linkerFactory,
            _baseToken,
            _initialSharePrice,
            _checkpointsPerTerm,
            _checkpointDuration,
            _timeStretch,
            _fees,
            _governance
        )
    {} // solhint-disable-line no-empty-blocks

    /// @notice Allows anyone to mint a new checkpoint.
    /// @param _checkpointTime The time of the checkpoint to create.
    function checkpoint(uint256 _checkpointTime) public override {
        // If the checkpoint has already been set, return early.
        if (checkpoints[_checkpointTime].sharePrice != 0) {
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
            _applyCheckpoint(latestCheckpoint, _pricePerShare());
        } else {
            for (uint256 time = _checkpointTime; ; time += checkpointDuration) {
                uint256 closestSharePrice = checkpoints[time].sharePrice;
                if (time == latestCheckpoint) {
                    closestSharePrice = _pricePerShare();
                }
                if (closestSharePrice != 0) {
                    _applyCheckpoint(_checkpointTime, closestSharePrice);
                    break;
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
    /// @param _poolInfo An in-memory representation of the pool's state.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @return openSharePrice The open share price of the latest checkpoint.
    function _applyCheckpoint(
        IHyperdrive.PoolInfo memory _poolInfo,
        uint256 _checkpointTime
    ) internal override returns (uint256 openSharePrice) {
        // Return early if the checkpoint has already been updated.
        if (
            checkpoints[_checkpointTime].sharePrice != 0 ||
            _checkpointTime > block.timestamp
        ) {
            return checkpoints[_checkpointTime].sharePrice;
        }

        // Create the share price checkpoint.
        checkpoints[_checkpointTime].sharePrice = _poolInfo
            .sharePrice
            .toUint128();

        // Pay out the long withdrawal pool for longs that have matured.
        uint256 maturedLongsAmount = totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _checkpointTime)
        ];
        if (maturedLongsAmount > 0) {
            _applyCloseLong(
                _poolInfo,
                maturedLongsAmount,
                0,
                maturedLongsAmount.divDown(_poolInfo.sharePrice),
                0,
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
                maturedShortsAmount.divDown(_poolInfo.sharePrice),
                0,
                _checkpointTime,
                _poolInfo.sharePrice
            );
        }

        return checkpoints[_checkpointTime].sharePrice;
    }
}
