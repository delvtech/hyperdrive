// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "./libraries/SafeCast.sol";
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
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _dataProvider The address of the data provider.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory
    ) HyperdriveBase(_config, _dataProvider, _linkerCodeHash, _linkerFactory) {} // solhint-disable-line no-empty-blocks

    /// @notice Allows anyone to mint a new checkpoint.
    /// @param _checkpointTime The time of the checkpoint to create.
    function checkpoint(uint256 _checkpointTime) public override {
        // If the checkpoint has already been set, return early.
        if (_checkpoints[_checkpointTime].sharePrice != 0) {
            return;
        }

        // If the checkpoint time isn't divisible by the checkpoint duration
        // or is in the future, it's an invalid checkpoint and we should
        // revert.
        uint256 latestCheckpoint = _latestCheckpoint();
        if (
            _checkpointTime % _checkpointDuration != 0 ||
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
            for (
                uint256 time = _checkpointTime;
                ;
                time += _checkpointDuration
            ) {
                uint256 closestSharePrice = _checkpoints[time].sharePrice;
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

    /// @dev Creates a new checkpoint if necessary.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _sharePrice The current share price.
    /// @return openSharePrice The open share price of the latest checkpoint.
    function _applyCheckpoint(
        uint256 _checkpointTime,
        uint256 _sharePrice
    ) internal override returns (uint256 openSharePrice) {
        // Return early if the checkpoint has already been updated.

        IHyperdrive.Checkpoint storage checkpoint = _checkpoints[
            _checkpointTime
        ];
        if (checkpoint.sharePrice != 0 || _checkpointTime > block.timestamp) {
            return checkpoint.sharePrice;
        }

        // Create the share price checkpoint.
        checkpoint.sharePrice = _sharePrice.toUint128();

        // Pay out the long withdrawal pool for longs that have matured.
        uint256 maturedLongsAmount = _totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _checkpointTime)
        ];
        if (maturedLongsAmount > 0) {
            _applyCloseLong(
                maturedLongsAmount,
                0,
                maturedLongsAmount.divDown(_sharePrice),
                0,
                _checkpointTime,
                _sharePrice
            );
        }

        // Pay out the short withdrawal pool for shorts that have matured.
        uint256 maturedShortsAmount = _totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _checkpointTime)
        ];
        if (maturedShortsAmount > 0) {
            _applyCloseShort(
                maturedShortsAmount,
                0,
                maturedShortsAmount.divDown(_sharePrice),
                0,
                _checkpointTime,
                _sharePrice
            );
        }

        return checkpoint.sharePrice;
    }
}
