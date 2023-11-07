// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";
import { SafeCast } from "../libraries/SafeCast.sol";
import { HyperdriveLP } from "./HyperdriveLP.sol";

/// @author DELV
/// @title HyperdriveShort
/// @notice Implements the short accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveShort is HyperdriveLP {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @dev Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    /// @param _maxDeposit The most the user expects to deposit for this trade.
    /// @param _minSharePrice The minium share price at which to open the long.
    ///        This allows traders to protect themselves from opening a long in
    ///        a checkpoint where negative interest has accrued.
    /// @param _options The options that configure how the trade is settled.
    /// @return The maturity time of the short.
    /// @return The amount the user deposited for this trade.
    function _openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        uint256 _minSharePrice,
        IHyperdrive.Options calldata _options
    ) internal nonReentrant isNotPaused returns (uint256, uint256) {
        // Check that the message value and base amount are valid.
        _checkMessageValue();
        if (_bondAmount < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // Perform a checkpoint and compute the amount of interest the short
        // would have received if they opened at the beginning of the checkpoint.
        // Since the short will receive interest from the beginning of the
        // checkpoint, they will receive this backdated interest back at closing.
        uint256 sharePrice = _pricePerShare();
        if (sharePrice < _minSharePrice) {
            revert IHyperdrive.MinimumSharePrice();
        }
        uint256 latestCheckpoint = _latestCheckpoint();
        uint256 openSharePrice = _applyCheckpoint(latestCheckpoint, sharePrice);

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds sold to the beginning of the checkpoint.
        uint256 maturityTime = latestCheckpoint + _positionDuration;
        uint256 shareReservesDelta;
        uint256 traderDeposit;
        {
            uint256 totalGovernanceFee;
            (
                traderDeposit,
                shareReservesDelta,
                totalGovernanceFee
            ) = _calculateOpenShort(_bondAmount, sharePrice, openSharePrice);

            // Trader deposit is in shares, so we need to ensure it matches the
            // options specified by the user.
            traderDeposit = _convertToOptionFromShares(
                traderDeposit,
                sharePrice,
                _options
            );

            // Attribute the governance fees.
            _governanceFeesAccrued += totalGovernanceFee;
        }

        // Take custody of the trader's deposit and ensure that the trader
        // doesn't pay more than their max deposit. The trader's deposit is
        // equal to the proceeds that they would receive if they closed
        // immediately (without fees).
        if (_maxDeposit < traderDeposit) {
            revert IHyperdrive.OutputLimit();
        }
        (uint256 sharesDeposited, ) = _deposit(traderDeposit, _options);

        // Apply the state updates caused by opening the short.
        _applyOpenShort(
            _bondAmount,
            shareReservesDelta,
            sharePrice,
            maturityTime
        );

        // Mint the short tokens to the trader. The ID is a concatenation of the
        // current share price and the maturity time of the shorts.
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Short,
            maturityTime
        );
        uint256 bondAmount = _bondAmount; // Avoid stack too deep error.
        _mint(assetId, _options.destination, bondAmount);

        // Emit an OpenShort event.
        emit OpenShort(
            _options.destination,
            assetId,
            maturityTime,
            sharesDeposited.mulDown(sharePrice),
            sharePrice,
            bondAmount
        );

        return (maturityTime, traderDeposit);
    }

    /// @notice Closes a short position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of shorts to close.
    /// @param _minOutput The minimum output of this trade.
    /// @param _options The options that configure how the trade is settled.
    /// @return The amount of base tokens produced by closing this short
    function _closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) internal nonReentrant returns (uint256) {
        if (_bondAmount < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // Perform a checkpoint.
        uint256 sharePrice = _pricePerShare();
        _applyCheckpoint(_maturityTime, sharePrice);

        // Burn the shorts that are being closed.
        _burn(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _maturityTime),
            msg.sender,
            _bondAmount
        );

        // Calculate the changes to the reserves and the traders proceeds up
        // front. This will also verify that the calculated values don't break
        // any invariants.
        (
            uint256 bondReservesDelta,
            uint256 shareProceeds,
            uint256 shareReservesDelta,
            uint256 shareCurveDelta,
            int256 shareAdjustmentDelta,
            uint256 totalGovernanceFee
        ) = _calculateCloseShort(_bondAmount, sharePrice, _maturityTime);

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the short to the reserves and pay out the
        // withdrawal pool if necessary.
        uint256 bondAmount = _bondAmount; // Avoid stack too deep error.
        uint256 maturityTime = _maturityTime; // Avoid stack too deep error.
        uint256 sharePrice_ = sharePrice; // Avoid stack too deep error.
        if (block.timestamp < maturityTime) {
            // Attribute the governance fees.
            _governanceFeesAccrued += totalGovernanceFee;

            // Update the pool's state to account for the short being closed.
            _applyCloseShort(
                bondAmount,
                bondReservesDelta,
                shareReservesDelta,
                shareAdjustmentDelta,
                maturityTime
            );

            // Update the checkpoint and global longExposure
            uint256 checkpointTime = maturityTime - _positionDuration;
            int128 checkpointExposureBefore = int128(
                _checkpoints[checkpointTime].longExposure
            );
            _updateCheckpointLongExposureOnClose(
                bondAmount,
                shareCurveDelta,
                bondReservesDelta,
                shareReservesDelta,
                maturityTime,
                sharePrice_,
                false
            );
            _updateLongExposure(
                checkpointExposureBefore,
                _checkpoints[checkpointTime].longExposure
            );

            // Distribute the excess idle to the withdrawal pool.
            _distributeExcessIdle(sharePrice_);
        }

        // Withdraw the profit to the trader. This includes the proceeds from
        // the short sale as well as the variable interest that was collected
        // on the face value of the bonds.
        uint256 proceeds = _withdraw(shareProceeds, _options);

        // Enforce the user's minimum output.
        IHyperdrive.Options calldata options = _options; // Avoid stack too deep error.
        uint256 baseProceeds = _convertToBaseFromOption(
            proceeds,
            sharePrice,
            options
        );
        if (baseProceeds < _minOutput) {
            revert IHyperdrive.OutputLimit();
        }

        // Emit a CloseShort event.
        emit CloseShort(
            _options.destination,
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime),
            maturityTime,
            baseProceeds,
            sharePrice_,
            bondAmount
        );

        return proceeds;
    }

    /// @dev Applies an open short to the state. This includes updating the
    ///      reserves and maintaining the reserve invariants.
    /// @param _bondAmount The amount of bonds shorted.
    /// @param _shareReservesDelta The amount of shares paid to the curve.
    /// @param _sharePrice The share price.
    /// @param _maturityTime The maturity time of the long.
    function _applyOpenShort(
        uint256 _bondAmount,
        uint256 _shareReservesDelta,
        uint256 _sharePrice,
        uint256 _maturityTime
    ) internal {
        // Update the average maturity time of long positions.
        _marketState.shortAverageMaturityTime = uint256(
            _marketState.shortAverageMaturityTime
        )
            .updateWeightedAverage(
                _marketState.shortsOutstanding,
                _maturityTime * 1e18, // scale up to fixed point scale
                _bondAmount,
                true
            )
            .toUint128();

        // Apply the trading deltas to the reserves and increase the bond buffer
        // by the amount of bonds that were shorted. We don't need to add the
        // margin or pre-paid interest to the reserves because of the way that
        // the close short accounting works.
        uint128 shareReserves_ = _marketState.shareReserves -
            _shareReservesDelta.toUint128();
        _marketState.shareReserves = shareReserves_;
        _marketState.bondReserves += _bondAmount.toUint128();
        _marketState.shortsOutstanding += _bondAmount.toUint128();

        // TODO: We're not sure what causes the z >= zeta check to fail.
        // It may be unnecessary, but that needs to be proven before we can
        // remove it.
        //
        // The share reserves are decreased in this operation, so we need to
        // verify that our invariants that z >= z_min and z >= zeta
        // are satisfied. The former is checked when we check solvency (since
        // global exposure is greater than or equal to zero, z < z_min
        // implies z - e/c - z_min < 0.
        if (
            int256(uint256(_marketState.shareReserves)) <
            _marketState.shareAdjustment
        ) {
            revert IHyperdrive.InvalidShareReserves();
        }

        // Update the checkpoint's short deposits and decrease the long exposure.
        uint256 _latestCheckpoint = _latestCheckpoint();
        int128 checkpointExposureBefore = int128(
            _checkpoints[_latestCheckpoint].longExposure
        );
        _checkpoints[_latestCheckpoint].longExposure -= int128(
            _bondAmount.toUint128()
        );
        _updateLongExposure(
            checkpointExposureBefore,
            _checkpoints[_latestCheckpoint].longExposure
        );

        // Opening a short decreases the system's exposure because the short's
        // margin can be used to offset some of the long exposure. Despite this,
        // opening a short decreases the share reserves, which limits the amount
        // of capital available to back non-netted long exposure. Since both
        // quantities decrease, we need to check that the system is still solvent.
        if (!_isSolvent(_sharePrice)) {
            revert IHyperdrive.BaseBufferExceedsShareReserves();
        }

        // Distribute the excess idle to the withdrawal pool.
        _distributeExcessIdle(_sharePrice);
    }

    /// @dev Applies the trading deltas from a closed short to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of shorts that were closed.
    /// @param _bondReservesDelta The amount of bonds removed from the reserves.
    /// @param _shareReservesDelta The amount of shares added to the reserves.
    /// @param _shareAdjustmentDelta The amount to increase the share adjustment.
    /// @param _maturityTime The maturity time of the short.
    function _applyCloseShort(
        uint256 _bondAmount,
        uint256 _bondReservesDelta,
        uint256 _shareReservesDelta,
        int256 _shareAdjustmentDelta,
        uint256 _maturityTime
    ) internal {
        // Update the short average maturity time.
        uint128 shortsOutstanding_ = _marketState.shortsOutstanding;
        _marketState.shortAverageMaturityTime = uint256(
            _marketState.shortAverageMaturityTime
        )
            .updateWeightedAverage(
                shortsOutstanding_,
                _maturityTime * 1e18, // scale up to fixed point scale
                _bondAmount,
                false
            )
            .toUint128();

        // Decrease the amount of shorts outstanding.
        _marketState.shortsOutstanding =
            shortsOutstanding_ -
            _bondAmount.toUint128();

        // Update the reserves and the share adjustment.
        _marketState.shareReserves += _shareReservesDelta.toUint128();
        _marketState.shareAdjustment += _shareAdjustmentDelta.toInt128();
        _marketState.bondReserves -= _bondReservesDelta.toUint128();
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      opening a short. This calculation includes trading fees.
    /// @param _bondAmount The amount of bonds being sold to open the short.
    /// @param _sharePrice The current share price.
    /// @param _openSharePrice The share price at the beginning of the checkpoint.
    /// @return traderDeposit The deposit, in shares, required to open the short.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateOpenShort(
        uint256 _bondAmount,
        uint256 _sharePrice,
        uint256 _openSharePrice
    )
        internal
        view
        returns (
            uint256 traderDeposit,
            uint256 shareReservesDelta,
            uint256 totalGovernanceFee
        )
    {
        // Calculate the effect that opening the short should have on the pool's
        // reserves as well as the amount of shares the trader receives from
        // selling the shorted bonds at the market price.
        shareReservesDelta = HyperdriveMath.calculateOpenShort(
            _effectiveShareReserves(),
            _marketState.bondReserves,
            _bondAmount,
            _timeStretch,
            _sharePrice,
            _initialSharePrice
        );

        // If the base proceeds of selling the bonds is greater than the bond
        // amount, then the trade occurred in the negative interest domain. We
        // revert in these pathological cases.
        if (shareReservesDelta.mulDown(_sharePrice) > _bondAmount) {
            revert IHyperdrive.NegativeInterest();
        }

        // Calculate the fees charged to the user (totalCurveFee) and the portion
        // of those fees that are paid to governance (totalGovernanceFee).
        uint256 curveFee;
        uint256 governanceCurveFee;
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            _effectiveShareReserves(),
            _marketState.bondReserves,
            _initialSharePrice,
            _timeStretch
        );
        (
            curveFee, // flatFee
            ,
            governanceCurveFee, // governanceFlatFee (flat fee is always 0 on open)
            // totalGovernanceFee (equal to governanceCurveFee)
            ,

        ) = _calculateFeesGivenBonds(
            _bondAmount,
            ONE, // shorts are opened at the beginning of the term
            spotPrice,
            _sharePrice
        );

        // Subtract the total curve fee minus the governance curve fee to the
        // amount that will be subtracted from the share reserves. This ensures
        // that the LPs are credited with the fee the trader paid on the
        // curve trade minus the portion of the curve fee that was paid to
        // governance.
        //
        // shareReservesDelta, curveFee and governanceCurveFee are all
        // denominated in shares so we just need to subtract out the
        // governanceCurveFee from the shareReservesDelta since that fee isn't
        // reserved for the LPs.
        //
        // shares -= shares - shares
        shareReservesDelta -= curveFee - governanceCurveFee;

        // The trader will need to deposit capital to pay for the fixed rate,
        // the curve fee, the flat fee, and any back-paid interest that will be
        // received back upon closing the trade. If negative interest has
        // accrued during the current checkpoint, we set close share price to
        // equal the open share price. This ensures that shorts don't benefit
        // from negative interest that accrued during the current checkpoint.
        traderDeposit = HyperdriveMath.calculateShortProceeds(
            _bondAmount,
            // NOTE: We add the governance fee back to the share reserves
            // delta here because the trader will need to provide this in
            // their deposit.
            shareReservesDelta - governanceCurveFee,
            _openSharePrice,
            _sharePrice.max(_openSharePrice),
            _sharePrice,
            _flatFee
        );

        return (traderDeposit, shareReservesDelta, governanceCurveFee);
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      closing a short. This calculation includes trading fees.
    /// @param _bondAmount The amount of bonds being purchased to close the
    ///        short.
    /// @param _sharePrice The current share price.
    /// @param _maturityTime The maturity time of the short position.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return shareProceeds The proceeds in shares of closing the short.
    /// @return shareReservesDelta The shares added to the reserves.
    /// @return shareCurveDelta The curve portion of the proceeds that LPs
    ///         receive from the trader in shares.
    /// @return shareAdjustmentDelta The change in the share adjustment.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateCloseShort(
        uint256 _bondAmount,
        uint256 _sharePrice,
        uint256 _maturityTime
    )
        internal
        view
        returns (
            uint256 bondReservesDelta,
            uint256 shareProceeds,
            uint256 shareReservesDelta,
            uint256 shareCurveDelta,
            int256 shareAdjustmentDelta,
            uint256 totalGovernanceFee
        )
    {
        // Calculate the effect that closing the short should have on the pool's
        // reserves as well as the amount of shares the trader pays to buy the
        // bonds that they shorted back at the market price.
        {
            // Calculate the effect that closing the short should have on the
            // pool's reserves as well as the amount of shares the trader needs
            // to pay to purchase the shorted bonds at the market price.
            //
            // NOTE: We calculate the time remaining from the latest checkpoint
            // to ensure that opening/closing a position doesn't result in
            // immediate profit.
            uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
            (
                shareCurveDelta,
                bondReservesDelta,
                shareReservesDelta
            ) = HyperdriveMath.calculateCloseShort(
                _effectiveShareReserves(),
                _marketState.bondReserves,
                _bondAmount,
                timeRemaining,
                _timeStretch,
                _sharePrice,
                _initialSharePrice
            );

            // Ensure that the trader didn't purchase bonds at a negative interest
            // rate after accounting for fees.
            uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
                _effectiveShareReserves(),
                _marketState.bondReserves,
                _initialSharePrice,
                _timeStretch
            );
            if (
                _isNegativeInterest(
                    shareCurveDelta,
                    bondReservesDelta,
                    HyperdriveMath.calculateCloseShortMaxSpotPrice(
                        spotPrice,
                        _curveFee
                    )
                )
            ) {
                revert IHyperdrive.NegativeInterest();
            }

            // Calculate the fees charged to the user (totalCurveFee and
            // totalFlatFee) and the portion of those fees that are paid to
            // governance (governanceCurveFee and governanceFlatFee).
            uint256 bondAmount = _bondAmount; // Avoid stack too deep.
            uint256 sharePrice = _sharePrice; // Avoid stack too deep.
            uint256 curveFee;
            uint256 flatFee;
            uint256 governanceCurveFee;
            (
                curveFee,
                flatFee,
                governanceCurveFee, // governanceFlatFee
                ,
                totalGovernanceFee
            ) = _calculateFeesGivenBonds(
                bondAmount,
                timeRemaining,
                spotPrice,
                sharePrice
            );

            // Add the total curve fee minus the governance curve fee to the
            // amount that will be added to the share reserves. This ensures
            // that the LPs are credited with the fee the trader paid on the
            // curve trade minus the portion of the curve fee that was paid to
            // governance.
            //
            // shareCurveDelta, curveFee and governanceCurveFee are all
            // denominated in shares so we just need to subtract out the
            // governanceCurveFees from the shareCurveDelta since that fee isn't
            // reserved for the LPs
            shareCurveDelta += curveFee - governanceCurveFee;

            // Calculate the shareReservesDelta that the user must make to close
            // out the short. We add the curveFee (shares) and flatFee (shares)
            // to the shareReservesDelta to ensure that fees are collected.
            shareReservesDelta += curveFee + flatFee;
        }

        // Calculate the share proceeds owed to the short and account for
        // negative interest that accrued over the period.
        {
            uint256 openSharePrice = _checkpoints[
                _maturityTime - _positionDuration
            ].sharePrice;
            uint256 closeSharePrice = block.timestamp < _maturityTime
                ? _sharePrice
                : _checkpoints[_maturityTime].sharePrice;

            // Calculate the share proceeds owed to the short. We calculate this
            // before scaling the share payment for negative interest. Shorts
            // are responsible for paying for 100% of the negative interest, so
            // they aren't benefited when the payment to LPs is decreased due to
            // negative interest. Similarly, the governance fee is included in
            // the share payment. The LPs don't receive the governance fee, but
            // the short is responsible for paying it.
            shareProceeds = HyperdriveMath.calculateShortProceeds(
                _bondAmount,
                shareReservesDelta,
                openSharePrice,
                closeSharePrice,
                _sharePrice,
                _flatFee
            );

            // The governance fee isn't included in the share payment that is
            // added to the share reserves. We remove it here to simplify the
            // accounting updates.
            shareReservesDelta -= totalGovernanceFee;

            // Adjust the computed proceeds and delta for negative interest.
            // We also compute the share adjustment delta at this step to ensure
            // that we don't break our AMM invariant when we account for negative
            // interest and flat adjustments.
            (
                shareProceeds,
                shareReservesDelta,
                shareCurveDelta,
                shareAdjustmentDelta,
                totalGovernanceFee
            ) = HyperdriveMath.calculateNegativeInterestOnClose(
                shareProceeds,
                shareReservesDelta,
                shareCurveDelta,
                totalGovernanceFee,
                openSharePrice,
                closeSharePrice,
                false
            );
        }
    }
}
