// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { LPMath } from "../libraries/LPMath.sol";
import { SafeCast } from "../libraries/SafeCast.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
import { HyperdriveLong } from "./HyperdriveLong.sol";
import { HyperdriveShort } from "./HyperdriveShort.sol";

/// @author DELV
/// @notice Implements the checkpoint accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveCheckpoint is
    HyperdriveBase,
    HyperdriveLong,
    HyperdriveShort
{
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;

    /// @dev Attempts to mint a checkpoint with the specified checkpoint time.
    /// @param _checkpointTime The time of the checkpoint to create.
    function _checkpoint(uint256 _checkpointTime) internal {
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
    /// @return The opening share price of the latest checkpoint.
    function _applyCheckpoint(
        uint256 _checkpointTime,
        uint256 _sharePrice
    ) internal override returns (uint256) {
        // Return early if the checkpoint has already been updated.
        IHyperdrive.Checkpoint storage checkpoint_ = _checkpoints[
            _checkpointTime
        ];
        if (checkpoint_.sharePrice != 0 || _checkpointTime > block.timestamp) {
            return checkpoint_.sharePrice;
        }

        // Create the share price checkpoint.
        checkpoint_.sharePrice = _sharePrice.toUint128();

        // Collect the interest that has accrued since the last checkpoint.
        _collectZombieInterest(
            _marketState.zombieShareReserves,
            _checkpoints[_checkpointTime - _checkpointDuration].sharePrice,
            _sharePrice
        );

        // Close out all of the short positions that matured at the beginning of
        // this checkpoint. This ensures that shorts don't continue to collect
        // free variable interest and that LP's can withdraw the proceeds of
        // their side of the trade. Closing out shorts first helps with netting
        // by ensuring the LP funds that were netted with longs are back in the
        // shareReserves before we close out the longs.
        uint256 openSharePrice = _checkpoints[
            _checkpointTime - _positionDuration
        ].sharePrice;
        uint256 shortAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Short,
            _checkpointTime
        );
        uint256 maturedShortsAmount = _totalSupply[shortAssetId];
        bool positionsClosed;
        if (maturedShortsAmount > 0) {
            (
                uint256 shareProceeds,
                uint256 governanceFee
            ) = _calculateMaturedProceeds(
                    maturedShortsAmount,
                    _sharePrice,
                    openSharePrice,
                    false
                );
            _governanceFeesAccrued += governanceFee;
            _applyCloseShort(
                maturedShortsAmount,
                0,
                shareProceeds,
                int256(shareProceeds), // keep the effective share reserves constant
                _checkpointTime
            );
            uint256 shareReservesDelta = maturedShortsAmount.divDown(
                _sharePrice
            );
            shareProceeds = HyperdriveMath.calculateShortProceeds(
                maturedShortsAmount,
                shareReservesDelta,
                openSharePrice,
                _sharePrice,
                _sharePrice,
                _flatFee
            );
            _marketState.zombieShareReserves += shareProceeds.toUint128();
            positionsClosed = true;
        }

        // Close out all of the long positions that matured at the beginning of
        // this checkpoint.
        uint256 longAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            _checkpointTime
        );
        uint256 maturedLongsAmount = _totalSupply[longAssetId];
        if (maturedLongsAmount > 0) {
            (
                uint256 shareProceeds,
                uint256 governanceFee
            ) = _calculateMaturedProceeds(
                    maturedLongsAmount,
                    _sharePrice,
                    openSharePrice,
                    true
                );
            _governanceFeesAccrued += governanceFee;
            uint256 checkpointTime = _checkpointTime; // avoid stack too deep error
            _applyCloseLong(
                maturedLongsAmount,
                0,
                shareProceeds,
                int256(shareProceeds), // keep the effective share reserves constant
                checkpointTime
            );
            _marketState.zombieShareReserves += shareProceeds.toUint128();
            positionsClosed = true;
        }

        // If we closed any positions, update the global long exposure and
        // distribute any excess idle to the withdrawal pool.
        if (positionsClosed) {
            // Update the global long exposure. Since we've closed some matured
            // positions, we can reduce the long exposure for the matured
            // checkpoint to zero.
            _updateLongExposure(
                int256(maturedLongsAmount) - int256(maturedShortsAmount),
                0
            );

            // Distribute the excess idle to the withdrawal pool.
            _distributeExcessIdle(_sharePrice);
        }

        // Emit an event about the checkpoint creation that includes the LP
        // share price.
        uint256 presentValue = _sharePrice > 0
            ? LPMath
                .calculatePresentValue(_getPresentValueParams(_sharePrice))
                .mulDown(_sharePrice)
            : 0;
        uint256 lpTotalSupply = _totalSupply[AssetId._LP_ASSET_ID] +
            _totalSupply[AssetId._WITHDRAWAL_SHARE_ASSET_ID] -
            _withdrawPool.readyToWithdraw;
        uint256 lpSharePrice = lpTotalSupply == 0
            ? 0
            : presentValue.divDown(lpTotalSupply);
        emit CreateCheckpoint(
            _checkpointTime,
            _sharePrice,
            maturedShortsAmount,
            maturedLongsAmount,
            lpSharePrice
        );

        return _sharePrice;
    }

    /// @dev Calculates the proceeds of the holders of a given position at
    ///      maturity.
    /// @param _bondAmount The bond amount of the position.
    /// @param _sharePrice The current share price.
    /// @param _openSharePrice The share price at the beginning of the
    ///        position's checkpoint.
    /// @param _isLong A flag indicating whether or not the position is a long.
    /// @return shareProceeds The proceeds of the holders in shares.
    /// @return governanceFee The fee paid to governance in shares.
    function _calculateMaturedProceeds(
        uint256 _bondAmount,
        uint256 _sharePrice,
        uint256 _openSharePrice,
        bool _isLong
    ) internal view returns (uint256 shareProceeds, uint256 governanceFee) {
        // Calculate the share proceeds, flat fee, and governance fee. Since the
        // position is closed at maturity, the share proceeds are equal to the
        // bond amount divided by the share price.
        shareProceeds = _bondAmount.divDown(_sharePrice);
        uint256 flatFee = shareProceeds.mulDown(_flatFee);
        governanceFee = flatFee.mulDown(_governanceFee);

        // If the position is a long, the share proceeds are removed from the
        // share reserves. The proceeds are decreased by the flat fee because
        // the trader pays the flat fee. Most of the flat fee is paid to the
        // reserves; however, a portion of the flat fee is paid to governance.
        // With this in mind, we also increase the share proceeds by the
        // governance fee.
        if (_isLong) {
            shareProceeds -= flatFee - governanceFee;
        }
        // If the position is a short, the share proceeds are added to the share
        // reserves. The proceeds are increased by the flat fee because the pool
        // receives the flat fee. Most of the flat fee is paid to the reserves;
        // however, a portion of the flat fee is paid to governance. With this
        // in mind, we also decrease the share proceeds by the governance fee.
        else {
            shareProceeds += flatFee - governanceFee;
        }

        // If negative interest accrued over the period, the proceeds and
        // governance fee are given a "haircut" proportional to the negative
        // interest that accrued.
        if (_sharePrice < _openSharePrice) {
            shareProceeds = shareProceeds.mulDivDown(
                _sharePrice,
                _openSharePrice
            );
            governanceFee = governanceFee.mulDivDown(
                _sharePrice,
                _openSharePrice
            );
        }
    }
}
