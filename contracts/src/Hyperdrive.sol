// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
import { HyperdriveLong } from "./HyperdriveLong.sol";
import { HyperdriveShort } from "./HyperdriveShort.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { SafeCast } from "./libraries/SafeCast.sol";

import { Lib } from "../../test/utils/Lib.sol";
import "forge-std/console2.sol";

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
    using Lib for *;

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
            revert IHyperdrive.InvalidCheckpointTime();
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
        IHyperdrive.Checkpoint storage checkpoint_ = _checkpoints[
            _checkpointTime
        ];
        if (checkpoint_.sharePrice != 0 || _checkpointTime > block.timestamp) {
            return _checkpoints[_checkpointTime].sharePrice;
        }

        // Create the share price checkpoint.
        checkpoint_.sharePrice = _sharePrice.toUint128();

        // Pay out the long withdrawal pool for longs that have matured.
        uint256 maturedLongsAmount = _totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _checkpointTime)
        ];
        if (maturedLongsAmount > 0) {
            uint256 shareProceeds = maturedLongsAmount.divDown(_sharePrice);
            uint256 flatFee = shareProceeds.mulDown(_flatFee);
            uint256 govFee = flatFee.mulDown(_governanceFee);

            // Add accrued governance fees to the totalGovernanceFeesAccrued in terms of shares
            _governanceFeesAccrued += govFee;

            // Reduce shareProceeds by the flatFeeCharged, and less the govFee from the amount as it doesn't count
            // towards reserves. shareProceeds will only be used to update reserves, so its fine to take fees here.
            shareProceeds -= flatFee - govFee;

            _applyCloseLong(
                maturedLongsAmount,
                0,
                shareProceeds,
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
            uint256 shareProceeds = maturedShortsAmount.divDown(_sharePrice);
            uint256 flatFee = shareProceeds.mulDown(_flatFee);
            uint256 govFee = flatFee.mulDown(_governanceFee);

            // Add accrued governance fees to the totalGovernanceFeesAccrued in terms of shares
            _governanceFeesAccrued += govFee;

            // Increase shareProceeds by the flatFeeCharged, and less the govFee from the amount as it doesn't count
            // towards reserves. shareProceeds will only be used to update reserves, so its fine to take fees here.
            shareProceeds += flatFee - govFee;

            _applyCloseShort(
                maturedShortsAmount,
                0,
                shareProceeds,
                0,
                _checkpointTime,
                _sharePrice
            );
        }

        return checkpoint_.sharePrice;
    }

    // this method calculates the most up to date global exposure value
    function _getCurrentExposure() internal view override returns (int256) {
        return _exposure;
    }
}
