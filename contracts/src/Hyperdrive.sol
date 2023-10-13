// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
import { HyperdriveLong } from "./HyperdriveLong.sol";
import { HyperdriveShort } from "./HyperdriveShort.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { FixedPointMath, ONE } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { SafeCast } from "./libraries/SafeCast.sol";

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
    /// @dev Even if the checkpoint has already been minted, this function will
    ///      record any negative interest that accrued since the last checkpoint.
    /// @param _checkpointTime The time of the checkpoint to create.
    function checkpoint(uint256 _checkpointTime) public override {
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
            // Record any negative interest that accrued in this checkpoint.
            _recordNegativeInterest(
                _checkpointTime,
                checkpoint_.sharePrice,
                _sharePrice,
                false
            );

            return checkpoint_.sharePrice;
        }

        // Mint this checkpoint and record any negative interest that accrued
        // since the previous checkpoint.
        checkpoint_.sharePrice = _sharePrice.toUint128();
        _recordNegativeInterest(
            _checkpointTime,
            // FIXME: Explain why it's fine for this to be zero.
            _checkpoints[_checkpointTime - _checkpointDuration].sharePrice,
            _sharePrice,
            true
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
        uint256 maturedShortsAmount = _totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _checkpointTime)
        ];
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
            positionsClosed = true;
        }

        // Close out all of the long positions that matured at the beginning of
        // this checkpoint.
        uint256 maturedLongsAmount = _totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _checkpointTime)
        ];
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
            _applyCloseLong(
                maturedLongsAmount,
                0,
                shareProceeds,
                int256(shareProceeds), // keep the effective share reserves constant
                _checkpointTime
            );
            positionsClosed = true;
        }

        // Update the checkpoint and global longExposure
        if (positionsClosed) {
            uint256 maturityTime = _checkpointTime - _positionDuration;
            int128 checkpointExposureBefore = int128(
                _checkpoints[maturityTime].longExposure
            );
            _checkpoints[maturityTime].longExposure = 0;
            _updateLongExposure(
                checkpointExposureBefore,
                _checkpoints[maturityTime].longExposure
            );

            // Distribute the excess idle to the withdrawal pool.
            //
            // NOTE: It's important that this is done after all of the positions
            // have been closed because we turn off negative interest mode
            // before closing the matured positions.
            _distributeExcessIdle(_sharePrice);
        }

        return _sharePrice;
    }

    // FIXME: In order to really test this rigorously, I need to think of all
    // of the pathological share price paths that would result in this being
    // updated.
    //
    // FIXME: I need to test different kinds of checkpoint gaps to verify that
    // negative interest will always be recorded.
    //
    /// @dev Records any negative interest that has accrued since the previous
    ///      checkpoint. It's possible for negative interest to be missed if
    ///      some checkpoints are skipped, but negative interest can always be
    ///      recorded by minting the current checkpoint and the checkpoint
    ///      immediately after the last checkpoint before the negative interest.
    /// @param _checkpointTime The time of the checkpoint that we're evaluating.
    /// @param _previousCheckpointSharePrice The share price of the previous
    ///       checkpoint. If we are on a checkpoint boundary, this is the share
    ///       price of the checkpoint before the checkpoint that we're
    ///       evaluating. Otherwise, this is the share price of the checkpoint
    ///       that we're evaluating.
    /// @param _sharePrice The current share price.
    /// @param _isCheckpointBoundary A flag indicating whether or not the
    ///        checkpoint that we're evaluating is being minted or if it has
    ///        already been minted.
    function _recordNegativeInterest(
        uint256 _checkpointTime,
        uint256 _previousCheckpointSharePrice,
        uint256 _sharePrice,
        bool _isCheckpointBoundary
    ) internal {
        // If we are recording negative interest on a checkpoint boundary, then
        // any negative interest that is found will be recorded as occurring in
        // the previous checkpoint and expiring when positions from the previous
        // checkpoint mature. Otherwise, the negative interest will be recorded
        // as occurring in this checkpoint and expiring when positions from this
        // checkpoint mature.
        uint256 maturityTime = _checkpointTime + _positionDuration;
        if (_isCheckpointBoundary) {
            maturityTime -= _checkpointDuration;
        }

        // If we have already recorded negative interest for this maturity time,
        // we don't need to do anything.
        uint256 referenceMaturityTime = _marketState
            .negativeInterestReferenceMaturityTime;
        if (maturityTime == referenceMaturityTime && !_isCheckpointBoundary) {
            return;
        }

        // If the share price has fallen below the previous checkpoint share
        // price, then we need to record negative interest. We only record
        // negative interest that exceeds a tolerance to avoid triggering
        // negative interest mode caused by imperceptible rounding errors.
        uint256 referenceSharePrice = _marketState
            .negativeInterestReferenceSharePrice;
        if (
            _sharePrice.mulDown(ONE + _negativeInterestTolerance) <
            _previousCheckpointSharePrice
        ) {
            // The negative interest mode needs to use a lower bound for the
            // present value to avoid LPs racing to the bottom. With this in
            // mind we choose the maximum of the previous checkpoint share price
            // and the reference share price and the maximum of this
            // checkpoint's maturity time and the reference maturity time.
            if (_previousCheckpointSharePrice > referenceSharePrice) {
                _marketState
                    .negativeInterestReferenceSharePrice = _previousCheckpointSharePrice
                    .toUint128();
            }
            if (maturityTime > referenceMaturityTime) {
                _marketState
                    .negativeInterestReferenceMaturityTime = maturityTime
                    .toUint128();
            }
        }
        // Negative interest hasn't accrued in this checkpoint, so if we are on
        // a checkpoint boundary, we check to see if we can stop tracking
        // negative interest from earlier checkpoints. We only do this pruning
        // on a checkpoint boundary to avoid pathological scenarios with share
        // price fluctuations between checkpoint boundaries.
        else if (referenceSharePrice > 0 && _isCheckpointBoundary) {
            // If the current share price is greater than or equal to the
            // reference share price, then any negative interest that was being
            // tracked has been resolved. Similarly, if the checkpoint time is
            // greater than or equal to the reference maturity time, then any
            // positions that accrued negative interest will be closed.
            if (
                _sharePrice >= referenceSharePrice ||
                // NOTE: Even though we subtracted the checkpoint duration from
                // the maturity time (since it is a checkpoint boundary), we use
                // the unaltered checkpoint time for this check. We don't need
                // to wait an additional checkpoint to reset old negative
                // interest.
                _checkpointTime >= referenceMaturityTime
            ) {
                delete _marketState.negativeInterestReferenceSharePrice;
                delete _marketState.negativeInterestReferenceMaturityTime;
            }
        }
    }

    /// @dev Calculates the proceeds of the long holders of a given position at
    ///      maturity. The long holders will be the LPs if the position is a
    ///      short.
    /// @param _bondAmount The bond amount of the position.
    /// @param _sharePrice The current share price.
    /// @param _openSharePrice The share price at the beginning of the
    ///        position's checkpoint.
    /// @param _isLong A flag indicating whether or not the position is a long.
    /// @return shareProceeds The proceeds of the long holders in shares.
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
