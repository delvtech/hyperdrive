// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveEvents } from "../interfaces/IHyperdriveEvents.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";
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
    IHyperdriveEvents,
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
        if (_checkpoints[_checkpointTime].vaultSharePrice != 0) {
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
        // vault share price. Otherwise, we use a linear search to find the
        // closest vault share price and use that to perform the checkpoint.
        if (_checkpointTime == latestCheckpoint) {
            _applyCheckpoint(latestCheckpoint, _pricePerVaultShare());
        } else {
            for (
                uint256 time = _checkpointTime;
                ;
                time += _checkpointDuration
            ) {
                uint256 closestVaultSharePrice = _checkpoints[time]
                    .vaultSharePrice;
                if (time == latestCheckpoint) {
                    closestVaultSharePrice = _pricePerVaultShare();
                }
                if (closestVaultSharePrice != 0) {
                    _applyCheckpoint(_checkpointTime, closestVaultSharePrice);
                    break;
                }
            }
        }
    }

    /// @dev Creates a new checkpoint if necessary.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _vaultSharePrice The current vault share price.
    /// @return The opening vault share price of the latest checkpoint.
    function _applyCheckpoint(
        uint256 _checkpointTime,
        uint256 _vaultSharePrice
    ) internal override returns (uint256) {
        // Return early if the checkpoint has already been updated.
        IHyperdrive.Checkpoint storage checkpoint_ = _checkpoints[
            _checkpointTime
        ];
        if (
            checkpoint_.vaultSharePrice != 0 ||
            _checkpointTime > block.timestamp
        ) {
            return checkpoint_.vaultSharePrice;
        }

        // Create the vault share price checkpoint.
        checkpoint_.vaultSharePrice = _vaultSharePrice.toUint128();

        // Collect the interest that has accrued since the last checkpoint.
        _collectZombieInterest(_vaultSharePrice);

        // Close out all of the short positions that matured at the beginning of
        // this checkpoint. This ensures that shorts don't continue to collect
        // free variable interest and that LP's can withdraw the proceeds of
        // their side of the trade. Closing out shorts first helps with netting
        // by ensuring the LP funds that were netted with longs are back in the
        // shareReserves before we close out the longs.
        uint256 openVaultSharePrice = _checkpoints[
            _checkpointTime - _positionDuration
        ].vaultSharePrice;
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
                    _vaultSharePrice,
                    openVaultSharePrice,
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
            // NOTE: Round up to underestimate the short proceeds.
            uint256 shareReservesDelta = maturedShortsAmount.divUp(
                _vaultSharePrice
            );
            // NOTE: We divDown then mulDown to mimic the exact rounding that occurs
            // when the short is closed and the fee is calculated in _calculateFeesGivenBonds().
            shareReservesDelta += maturedShortsAmount
                .divDown(_vaultSharePrice)
                .mulDown(_flatFee);
            // NOTE: Round down to underestimate the short proceeds.
            shareProceeds = HyperdriveMath.calculateShortProceedsDown(
                maturedShortsAmount,
                shareReservesDelta,
                openVaultSharePrice,
                _vaultSharePrice,
                _vaultSharePrice,
                _flatFee
            );
            // NOTE: Round down to underestimate the short proceeds.
            _marketState.zombieBaseProceeds += shareProceeds
                .mulDown(_vaultSharePrice)
                .toUint112();
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
                    _vaultSharePrice,
                    openVaultSharePrice,
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

            // Subtract the governance fee out when we add
            // share proceeds to the zombie share reserves.
            shareProceeds -= governanceFee;

            // NOTE: Round down to underestimate the long proceeds.
            _marketState.zombieBaseProceeds += shareProceeds
                .mulDown(_vaultSharePrice)
                .toUint112();
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
            _distributeExcessIdle(_vaultSharePrice);
        }

        // Emit an event about the checkpoint creation that includes the LP
        // share price.
        emit CreateCheckpoint(
            _checkpointTime,
            _vaultSharePrice,
            maturedShortsAmount,
            maturedLongsAmount,
            _calculateLPSharePrice(_vaultSharePrice)
        );

        return _vaultSharePrice;
    }

    /// @dev Calculates the proceeds of the holders of a given position at
    ///      maturity.
    /// @param _bondAmount The bond amount of the position.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _openVaultSharePrice The vault share price at the beginning of
    ///        the position's checkpoint.
    /// @param _isLong A flag indicating whether or not the position is a long.
    /// @return shareProceeds The proceeds of the holders in shares.
    /// @return governanceFee The fee paid to governance in shares.
    function _calculateMaturedProceeds(
        uint256 _bondAmount,
        uint256 _vaultSharePrice,
        uint256 _openVaultSharePrice,
        bool _isLong
    ) internal view returns (uint256 shareProceeds, uint256 governanceFee) {
        // Calculate the share proceeds, flat fee, and governance fee. Since the
        // position is closed at maturity, the share proceeds are equal to the
        // bond amount divided by the vault share price.
        //
        // NOTE: Round down to underestimate the share proceeds, flat fee, and
        // governance fee.
        shareProceeds = _bondAmount.divDown(_vaultSharePrice);
        uint256 flatFee = shareProceeds.mulDown(_flatFee);
        governanceFee = flatFee.mulDown(_governanceLPFee);

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
        if (_vaultSharePrice < _openVaultSharePrice) {
            // NOTE: Round down to underestimate the proceeds.
            shareProceeds = shareProceeds.mulDivDown(
                _vaultSharePrice,
                _openVaultSharePrice
            );

            // NOTE: Round down to underestimate the governance fee.
            governanceFee = governanceFee.mulDivDown(
                _vaultSharePrice,
                _openVaultSharePrice
            );
        }
    }
}
