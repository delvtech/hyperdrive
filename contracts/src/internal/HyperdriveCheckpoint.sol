// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ExcessivelySafeCall } from "nomad/ExcessivelySafeCall.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveCheckpointRewarder } from "../interfaces/IHyperdriveCheckpointRewarder.sol";
import { IHyperdriveEvents } from "../interfaces/IHyperdriveEvents.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";
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
    using ExcessivelySafeCall for address;
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;

    /// @dev Attempts to mint a checkpoint with the specified checkpoint time.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _maxIterations The number of iterations to use in the Newton's
    ///        method component of `_distributeExcessIdleSafe`. This defaults to
    ///        `LPMath.SHARE_PROCEEDS_MAX_ITERATIONS` if the specified value is
    ///        smaller than the constant.
    function _checkpoint(
        uint256 _checkpointTime,
        uint256 _maxIterations
    ) internal nonReentrant {
        // If the checkpoint has already been set, attempt to distribute excess
        // idle and return early.
        uint256 vaultSharePrice = _pricePerVaultShare();
        if (_checkpoints[_checkpointTime].vaultSharePrice != 0) {
            // Distribute the excess idle to the withdrawal pool. If the
            // distribute excess idle calculation fails, we proceed with the
            // calculation since checkpoints should be minted regardless of
            // whether idle could be distributed.
            _distributeExcessIdleSafe(vaultSharePrice, _maxIterations);

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

        // Apply the checkpoint.
        _applyCheckpoint(
            _checkpointTime,
            vaultSharePrice,
            _maxIterations,
            false
        );
    }

    /// @dev Creates a new checkpoint if necessary.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _maxIterations The number of iterations to use in the Newton's
    ///        method component of `_distributeExcessIdleSafe`. This defaults to
    ///        `LPMath.SHARE_PROCEEDS_MAX_ITERATIONS` if the specified value is
    ///        smaller than the constant.
    /// @param _isTrader A boolean indicating whether or not the checkpoint was
    ///        minted by a trader or by someone calling checkpoint directly.
    /// @return The opening vault share price of the checkpoint.
    function _applyCheckpoint(
        uint256 _checkpointTime,
        uint256 _vaultSharePrice,
        uint256 _maxIterations,
        bool _isTrader
    ) internal override returns (uint256) {
        // Return early if the checkpoint has already been updated.
        IHyperdrive.Checkpoint storage checkpoint = _checkpoints[
            _checkpointTime
        ];
        if (
            checkpoint.vaultSharePrice != 0 || _checkpointTime > block.timestamp
        ) {
            return checkpoint.vaultSharePrice;
        }

        // If the checkpoint time is the latest checkpoint, we use the current
        // vault share price and spot price. Otherwise, we use a linear search
        // to find the closest non-zero vault share price and use that to
        // perform the checkpoint. We use the weighted spot price from the
        // checkpoint with the closest vault share price to populate the
        // weighted spot price.
        uint256 checkpointVaultSharePrice;
        uint256 checkpointWeightedSpotPrice;
        uint256 latestCheckpoint = _latestCheckpoint();
        {
            uint256 nextCheckpointTime = _checkpointTime + _checkpointDuration;
            for (; nextCheckpointTime < latestCheckpoint; ) {
                // If the time isn't the latest checkpoint, we check to see if
                // the checkpoint's vault share price is non-zero. If it is,
                // that is the vault share price that we'll use to create the
                // new checkpoint. We'll use the corresponding weighted spot
                // price to instantiate the weighted spot price for the new
                // checkpoint.
                uint256 futureVaultSharePrice = _checkpoints[nextCheckpointTime]
                    .vaultSharePrice;
                if (futureVaultSharePrice != 0) {
                    checkpointVaultSharePrice = futureVaultSharePrice;
                    checkpointWeightedSpotPrice = _checkpoints[
                        nextCheckpointTime
                    ].weightedSpotPrice;
                    break;
                }

                // Update the next checkpoint time.
                unchecked {
                    nextCheckpointTime += _checkpointDuration;
                }
            }
            if (checkpointVaultSharePrice == 0) {
                checkpointVaultSharePrice = _vaultSharePrice;
                checkpointWeightedSpotPrice = HyperdriveMath.calculateSpotPrice(
                    _effectiveShareReserves(),
                    _marketState.bondReserves,
                    _initialVaultSharePrice,
                    _timeStretch
                );
            }
        }

        // Create the vault share price checkpoint.
        checkpoint.vaultSharePrice = checkpointVaultSharePrice.toUint128();

        // Update the weighted spot price for the previous checkpoint.
        _updateWeightedSpotPrice(
            _checkpointTime - _checkpointDuration,
            _checkpointTime,
            checkpointWeightedSpotPrice
        );

        // Update the weighted spot price for the current checkpoint.
        _updateWeightedSpotPrice(
            _checkpointTime,
            // NOTE: We use the block time as the update time for the
            // latest checkpoint. For past checkpoints, we use the end time of
            // the checkpoint.
            block.timestamp.min(_checkpointTime + _checkpointDuration),
            checkpointWeightedSpotPrice
        );

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
        uint256 checkpointTime = _checkpointTime; // avoid stack-too-deep
        uint256 vaultSharePrice = _vaultSharePrice; // avoid stack-too-deep
        if (maturedShortsAmount > 0) {
            // Since we're closing out short positions, we'll need to distribute
            // excess idle once the accounting updates have been performed.
            positionsClosed = true;

            // Apply the governance and LP proceeds from closing out the matured
            // short positions to the state.
            (
                uint256 shareProceeds,
                uint256 governanceFee
            ) = _calculateMaturedProceeds(
                    maturedShortsAmount,
                    openVaultSharePrice,
                    checkpointVaultSharePrice,
                    vaultSharePrice,
                    false
                );
            _governanceFeesAccrued += governanceFee;
            _applyCloseShort(
                maturedShortsAmount,
                0,
                shareProceeds,
                shareProceeds.toInt256(), // keep the effective share reserves constant
                checkpointTime
            );

            // Add the governance fee back to the share proceeds. We removed it
            // from the LP's share proceeds since the fee is paid to governance;
            // however, the shorts must pay the flat fee.
            shareProceeds += governanceFee;

            // Calculate the share proceeds owed to the matured short positions.
            // Since the shorts have matured and the bonds have matured to a
            // value of 1, this is the amount of variable interest that the
            // shorts earned minus the flat fee.
            //
            // NOTE: Round down to underestimate the short proceeds.
            shareProceeds = HyperdriveMath.calculateShortProceedsDown(
                maturedShortsAmount,
                shareProceeds,
                openVaultSharePrice,
                checkpointVaultSharePrice,
                vaultSharePrice,
                _flatFee
            );

            // Add the short proceeds to the zombie base proceeds and share
            // reserves.
            //
            // NOTE: Round down to underestimate the short proceeds.
            _marketState.zombieBaseProceeds += shareProceeds
                .mulDown(vaultSharePrice)
                .toUint112();
            _marketState.zombieShareReserves += shareProceeds.toUint128();
        }

        // Close out all of the long positions that matured at the beginning of
        // this checkpoint.
        uint256 longAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            checkpointTime
        );
        uint256 maturedLongsAmount = _totalSupply[longAssetId];
        if (maturedLongsAmount > 0) {
            // Since we're closing out long positions, we'll need to distribute
            // excess idle once the accounting updates have been performed.
            positionsClosed = true;

            // Apply the governance and LP proceeds from closing out the matured
            // long positions to the state.
            (
                uint256 shareProceeds,
                uint256 governanceFee
            ) = _calculateMaturedProceeds(
                    maturedLongsAmount,
                    openVaultSharePrice,
                    checkpointVaultSharePrice,
                    vaultSharePrice,
                    true
                );
            _governanceFeesAccrued += governanceFee;
            _applyCloseLong(
                maturedLongsAmount,
                0,
                shareProceeds,
                shareProceeds.toInt256(), // keep the effective share reserves constant
                checkpointTime
            );

            // Subtract the governance fee out when we add
            // share proceeds to the zombie share reserves.
            shareProceeds -= governanceFee;

            // Add the long proceeds to the zombie base proceeds and share
            // reserves.
            //
            // NOTE: Round down to underestimate the long proceeds.
            _marketState.zombieBaseProceeds += shareProceeds
                .mulDown(vaultSharePrice)
                .toUint112();
            _marketState.zombieShareReserves += shareProceeds.toUint128();
        }

        // If we closed any positions, update the global long exposure and
        // distribute any excess idle to the withdrawal pool.
        if (positionsClosed) {
            // Update the global long exposure. Since we've closed some matured
            // positions, we can reduce the long exposure for the matured
            // checkpoint to zero.
            _updateLongExposure(
                maturedLongsAmount.toInt256() - maturedShortsAmount.toInt256(),
                0
            );

            // Distribute the excess idle to the withdrawal pool. If the
            // distribute excess idle calculation fails, we proceed with the
            // calculation since checkpoints should be minted regardless of
            // whether idle could be distributed.
            uint256 maxIterations = _maxIterations; // avoid stack-too-deep
            _distributeExcessIdleSafe(vaultSharePrice, maxIterations);
        }

        // Emit an event about the checkpoint creation that includes the LP
        // share price. If the LP share price calculation fails, we proceed in
        // minting the checkpoint and just emit the LP share price as zero. This
        // ensures that the system's liveness isn't impacted by temporarily
        // being unable to calculate the present value.
        (uint256 lpSharePrice, ) = _calculateLPSharePriceSafe(vaultSharePrice);
        emit CreateCheckpoint(
            checkpointTime,
            checkpointVaultSharePrice,
            vaultSharePrice,
            maturedShortsAmount,
            maturedLongsAmount,
            lpSharePrice
        );

        // Claim the checkpoint reward on behalf of the sender.
        //
        // NOTE: We do this in a low-level call and ignore the status to ensure
        // that the checkpoint will be minted regardless of whether or not the
        // call succeeds. Furthermore, we use the `ExcessivelySafeCall` library
        // to prevent returndata bombing.
        bool isTrader = _isTrader; // avoid stack-too-deep
        address checkpointRewarder = _adminController.checkpointRewarder();
        if (checkpointRewarder != address(0)) {
            checkpointRewarder.excessivelySafeCall(
                gasleft(),
                0, // value of 0
                0, // max copy of 0 bytes
                abi.encodeCall(
                    IHyperdriveCheckpointRewarder.claimCheckpointReward,
                    (msg.sender, checkpointTime, isTrader)
                )
            );
        }

        return checkpointVaultSharePrice;
    }

    /// @dev Calculates the proceeds of the holders of a given position at
    ///      maturity.
    /// @param _bondAmount The bond amount of the position.
    /// @param _openVaultSharePrice The vault share price from the position's
    ///        starting checkpoint.
    /// @param _closeVaultSharePrice The vault share price from the position's
    ///        ending checkpoint.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _isLong A flag indicating whether or not the position is a long.
    /// @return shareProceeds The proceeds of the holders in shares.
    /// @return governanceFee The fee paid to governance in shares.
    function _calculateMaturedProceeds(
        uint256 _bondAmount,
        uint256 _openVaultSharePrice,
        uint256 _closeVaultSharePrice,
        uint256 _vaultSharePrice,
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
        if (_closeVaultSharePrice < _openVaultSharePrice) {
            // NOTE: Round down to underestimate the proceeds.
            shareProceeds = shareProceeds.mulDivDown(
                _closeVaultSharePrice,
                _openVaultSharePrice
            );

            // NOTE: Round down to underestimate the governance fee.
            governanceFee = governanceFee.mulDivDown(
                _closeVaultSharePrice,
                _openVaultSharePrice
            );
        }
    }
}
