// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveEvents } from "../interfaces/IHyperdriveEvents.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { Errors } from "../libraries/Errors.sol";
import { FixedPointMath, ONE } from "../libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";
import { LPMath } from "../libraries/LPMath.sol";
import { SafeCast } from "../libraries/SafeCast.sol";
import { HyperdriveLP } from "./HyperdriveLP.sol";

/// @author DELV
/// @title HyperdriveShort
/// @notice Implements the short accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveShort is IHyperdriveEvents, HyperdriveLP {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @dev Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    /// @param _maxDeposit The most the user expects to deposit for this trade.
    ///        The units of this quantity are either base or vault shares,
    ///        depending on the value of `_options.asBase`.
    /// @param _minVaultSharePrice The minimum vault share price at which to open
    ///        the short. This allows traders to protect themselves from opening
    ///        a short in a checkpoint where negative interest has accrued.
    /// @param _options The options that configure how the trade is settled.
    /// @return The maturity time of the short.
    /// @return The amount the user deposited for this trade. The units of this
    ///         quantity are either base or vault shares, depending on the value
    ///         of `_options.asBase`.
    function _openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        uint256 _minVaultSharePrice,
        IHyperdrive.Options calldata _options
    ) internal nonReentrant isNotPaused returns (uint256, uint256) {
        // Check that the message value is valid.
        _checkMessageValue();

        // Check that the provided options are valid.
        _checkOptions(_options);

        // Ensure that the bond amount is greater than or equal to the minimum
        // transaction amount.
        if (_bondAmount < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // Perform a checkpoint and compute the amount of interest the short
        // would have received if they opened at the beginning of the checkpoint.
        // Since the short will receive interest from the beginning of the
        // checkpoint, they will receive this backdated interest back at closing.
        uint256 vaultSharePrice = _pricePerVaultShare();
        if (vaultSharePrice < _minVaultSharePrice) {
            revert IHyperdrive.MinimumSharePrice();
        }
        uint256 latestCheckpoint = _latestCheckpoint();
        uint256 openVaultSharePrice = _applyCheckpoint(
            _latestCheckpoint(),
            vaultSharePrice,
            LPMath.SHARE_PROCEEDS_MAX_ITERATIONS,
            true
        );

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds sold to the beginning of the checkpoint.
        // Note: All state deltas are derived from the external function input.
        uint256 maturityTime = latestCheckpoint + _positionDuration;
        uint256 baseDeposit;
        uint256 shareReservesDelta;
        uint256 totalGovernanceFee;
        {
            uint256 spotPrice;
            (
                baseDeposit,
                shareReservesDelta,
                totalGovernanceFee,
                spotPrice
            ) = _calculateOpenShort(
                _bondAmount,
                vaultSharePrice,
                openVaultSharePrice
            );

            // Attribute the governance fees.
            _governanceFeesAccrued += totalGovernanceFee;

            // Update the weighted spot price.
            _updateWeightedSpotPrice(
                latestCheckpoint,
                block.timestamp,
                spotPrice
            );
        }

        // Take custody of the trader's deposit and ensure that the trader
        // doesn't pay more than their max deposit. The trader's deposit is
        // equal to the proceeds that they would receive if they closed
        // immediately (without fees). Trader deposit is created to ensure that
        // the input to _deposit is denominated according to _options.
        //
        // NOTE: We don't check the maxDeposit against the output of deposit
        // because slippage from a deposit could cause a larger deposit taken
        // from the user to pass due to the shares being worth less after deposit.
        uint256 deposit = _convertToOptionFromBase(
            baseDeposit,
            vaultSharePrice,
            _options
        );
        if (_maxDeposit < deposit) {
            revert IHyperdrive.OutputLimit();
        }
        _deposit(deposit, _options);

        // Apply the state updates caused by opening the short.
        // Note: Updating the state using the result using the
        // deltas calculated from function inputs is consistent with
        // openLong.
        uint256 bondAmount = _bondAmount; // Avoid stack too deep error.
        _applyOpenShort(
            bondAmount,
            shareReservesDelta,
            vaultSharePrice,
            maturityTime
        );

        // Mint the short tokens to the trader.
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Short,
            maturityTime
        );
        IHyperdrive.Options calldata options = _options; // Avoid stack too deep error.
        _mint(assetId, options.destination, bondAmount);

        // Emit an OpenShort event.
        uint256 shareReservesDelta_ = shareReservesDelta; // Avoid stack too deep error.
        uint256 vaultSharePrice_ = vaultSharePrice; // Avoid stack too deep error.
        uint256 totalGovernanceFee_ = totalGovernanceFee; // Avoid stack too deep error.
        emit OpenShort(
            options.destination,
            assetId,
            maturityTime,
            deposit,
            vaultSharePrice_,
            options.asBase,
            // NOTE: We subtract out the governance fee from the share reserves
            // delta since the user is responsible for paying the governance
            // fee.
            (shareReservesDelta_ - totalGovernanceFee_).mulDown(
                vaultSharePrice_
            ),
            bondAmount,
            options.extraData
        );

        return (maturityTime, deposit);
    }

    /// @dev Closes a short position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of shorts to close.
    /// @param _minOutput The minimum output of this trade. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _options The options that configure how the trade is settled.
    /// @return The proceeds of closing this short. The units of this quantity
    ///         are either base or vault shares, depending on the value of
    ///         `_options.asBase`.
    function _closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) internal nonReentrant returns (uint256) {
        // Check that the provided options are valid.
        _checkOptions(_options);

        // Ensure that the bond amount is greater than or equal to the minimum
        // transaction amount.
        if (_bondAmount < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // If the short hasn't matured, we checkpoint the latest checkpoint.
        // Otherwise, we perform a checkpoint at the time the short matured.
        // This ensures the short and all of the other positions in the
        // checkpoint are closed.
        uint256 vaultSharePrice = _pricePerVaultShare();
        if (block.timestamp < _maturityTime) {
            _applyCheckpoint(
                _latestCheckpoint(),
                vaultSharePrice,
                LPMath.SHARE_PROCEEDS_MAX_ITERATIONS,
                true
            );
        } else {
            _applyCheckpoint(
                _maturityTime,
                vaultSharePrice,
                LPMath.SHARE_PROCEEDS_MAX_ITERATIONS,
                true
            );
        }

        // Burn the shorts that are being closed.
        _burn(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _maturityTime),
            msg.sender,
            _bondAmount
        );

        // Calculate the changes to the reserves and the traders proceeds up
        // front. This will also verify that the calculated values don't break
        // any invariants.
        // Note: All state deltas are derived from the external function input.
        (
            uint256 bondReservesDelta,
            uint256 shareProceeds,
            uint256 shareReservesDelta,
            int256 shareAdjustmentDelta,
            uint256 totalGovernanceFee,
            uint256 spotPrice
        ) = _calculateCloseShort(_bondAmount, vaultSharePrice, _maturityTime);

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the short to the reserves and pay out the
        // withdrawal pool if necessary.
        uint256 maturityTime = _maturityTime; // Avoid stack too deep error.
        if (block.timestamp < _maturityTime) {
            // Attribute the governance fees.
            _governanceFeesAccrued += totalGovernanceFee;

            // Update the weighted spot price.
            _updateWeightedSpotPrice(
                _latestCheckpoint(),
                block.timestamp,
                spotPrice
            );

            // Update the pool's state to account for the short being closed.
            _applyCloseShort(
                _bondAmount,
                bondReservesDelta,
                shareReservesDelta,
                shareAdjustmentDelta,
                maturityTime
            );

            // Update the global long exposure. Since we're closing a short, the
            // number of non-netted longs increases by the bond amount.
            int256 nonNettedLongs = _nonNettedLongs(_maturityTime);
            _updateLongExposure(
                nonNettedLongs - _bondAmount.toInt256(),
                nonNettedLongs
            );

            // Ensure that the system is still solvent after closing the shorts.
            // Closing shorts increases the share reserves, but it also
            // increases the long exposure.
            if (!_isSolvent(vaultSharePrice)) {
                Errors.throwInsufficientLiquidityError();
            }

            // Distribute the excess idle to the withdrawal pool. If the
            // distribute excess idle calculation fails, we revert to avoid
            // putting the system in an unhealthy state after the trade is
            // processed.
            bool success = _distributeExcessIdleSafe(vaultSharePrice);
            if (!success) {
                revert IHyperdrive.DistributeExcessIdleFailed();
            }
        } else {
            // Apply the zombie close to the state and adjust the share proceeds
            // to account for negative interest that might have accrued to the
            // zombie share reserves.
            shareProceeds = _applyZombieClose(shareProceeds, vaultSharePrice);

            // Distribute the excess idle to the withdrawal pool. If the
            // distribute excess idle calculation fails, we proceed with the
            // calculation since traders should be able to close their positions
            // at maturity regardless of whether idle could be distributed.
            _distributeExcessIdleSafe(vaultSharePrice);
        }

        // Withdraw the profit to the trader. This includes the proceeds from
        // the short sale as well as the variable interest that was collected
        // on the face value of the bonds.
        uint256 proceeds = _withdraw(shareProceeds, vaultSharePrice, _options);

        // Enforce the user's minimum output.
        //
        // NOTE: We use the value that is returned from the withdraw to check
        // against the minOutput because in the event of slippage on the
        // withdraw, we want it to be caught be the minOutput check.
        if (proceeds < _minOutput) {
            revert IHyperdrive.OutputLimit();
        }

        // Emit a CloseShort event.
        uint256 bondAmount = _bondAmount; // Avoid stack too deep error.
        uint256 shareReservesDelta_ = shareReservesDelta; // Avoid stack too deep error.
        uint256 totalGovernanceFee_ = totalGovernanceFee; // Avoid stack too deep error.
        uint256 vaultSharePrice_ = vaultSharePrice; // Avoid stack too deep error.
        IHyperdrive.Options calldata options = _options; // Avoid stack too deep error.
        emit CloseShort(
            msg.sender, // trader
            options.destination, // destination
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime),
            maturityTime,
            proceeds,
            vaultSharePrice_,
            options.asBase,
            // NOTE: We add the governance fee to the share reserves delta since
            // the user is responsible for paying the governance fee.
            (shareReservesDelta_ + totalGovernanceFee_).mulDown(
                vaultSharePrice_
            ),
            bondAmount,
            options.extraData
        );

        return proceeds;
    }

    /// @dev Applies an open short to the state. This includes updating the
    ///      reserves and maintaining the reserve invariants.
    /// @param _bondAmount The amount of bonds shorted.
    /// @param _shareReservesDelta The amount of shares paid to the curve.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _maturityTime The maturity time of the long.
    function _applyOpenShort(
        uint256 _bondAmount,
        uint256 _shareReservesDelta,
        uint256 _vaultSharePrice,
        uint256 _maturityTime
    ) internal {
        // If the share reserves would underflow when the short is opened, then
        // we revert with an insufficient liquidity error.
        uint256 shareReserves = _marketState.shareReserves;
        if (shareReserves < _shareReservesDelta) {
            Errors.throwInsufficientLiquidityError();
        }
        unchecked {
            shareReserves -= _shareReservesDelta;
        }

        // The share reserves are decreased in this operation, so we need to
        // verify that our invariants that z >= z_min and z - zeta >= z_min
        // are satisfied. The former is checked when we check solvency (since
        // global exposure is greater than or equal to zero, z < z_min
        // implies z - e/c - z_min < 0.
        if (
            HyperdriveMath.calculateEffectiveShareReserves(
                shareReserves,
                _marketState.shareAdjustment
            ) < _minimumShareReserves
        ) {
            Errors.throwInsufficientLiquidityError();
        }

        // Update the average maturity time of short positions.
        _marketState.shortAverageMaturityTime = uint256(
            _marketState.shortAverageMaturityTime
        )
            .updateWeightedAverage(
                _marketState.shortsOutstanding,
                _maturityTime * ONE, // scale up to fixed point scale
                _bondAmount,
                true
            )
            .toUint128();

        // Apply the trading deltas to the reserves and increase the bond buffer
        // by the amount of bonds that were shorted. We don't need to add the
        // margin or pre-paid interest to the reserves because of the way that
        // the close short accounting works.
        _marketState.shareReserves = shareReserves.toUint128();
        _marketState.bondReserves += _bondAmount.toUint128();
        _marketState.shortsOutstanding += _bondAmount.toUint128();

        // Update the global long exposure. Since we're opening a short, the
        // number of non-netted longs decreases by the bond amount.
        int256 nonNettedLongs = _nonNettedLongs(_maturityTime);
        _updateLongExposure(
            nonNettedLongs,
            nonNettedLongs - _bondAmount.toInt256()
        );

        // Opening a short decreases the system's exposure because the short's
        // margin can be used to offset some of the long exposure. Despite this,
        // opening a short decreases the share reserves, which limits the amount
        // of capital available to back non-netted long exposure. Since both
        // quantities decrease, we need to check that the system is still solvent.
        if (!_isSolvent(_vaultSharePrice)) {
            Errors.throwInsufficientLiquidityError();
        }

        // Distribute the excess idle to the withdrawal pool. If the distribute
        // excess idle calculation fails, we revert to avoid putting the system
        // in an unhealthy state after the trade is processed.
        bool success = _distributeExcessIdleSafe(_vaultSharePrice);
        if (!success) {
            revert IHyperdrive.DistributeExcessIdleFailed();
        }
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
                _maturityTime * ONE, // scale up to fixed point scale
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
    /// @param _vaultSharePrice The current vault share price.
    /// @param _openVaultSharePrice The vault share price at the beginning of
    ///        the checkpoint.
    /// @return baseDeposit The deposit, in base, required to open the short.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateOpenShort(
        uint256 _bondAmount,
        uint256 _vaultSharePrice,
        uint256 _openVaultSharePrice
    )
        internal
        view
        returns (
            uint256 baseDeposit,
            uint256 shareReservesDelta,
            uint256 totalGovernanceFee,
            uint256 spotPrice
        )
    {
        // Calculate the effect that opening the short should have on the pool's
        // reserves as well as the amount of shares the trader receives from
        // selling the shorted bonds at the market price.
        uint256 effectiveShareReserves = _effectiveShareReserves();
        shareReservesDelta = HyperdriveMath.calculateOpenShort(
            effectiveShareReserves,
            _marketState.bondReserves,
            _bondAmount,
            _timeStretch,
            _vaultSharePrice,
            _initialVaultSharePrice
        );

        // NOTE: Round up to make the check stricter.
        //
        // If the base proceeds of selling the bonds is greater than the bond
        // amount, then the trade occurred in the negative interest domain. We
        // revert in these pathological cases.
        if (shareReservesDelta.mulUp(_vaultSharePrice) > _bondAmount) {
            Errors.throwInsufficientLiquidityError();
        }

        // Calculate the current spot price.
        uint256 curveFee;
        uint256 governanceCurveFee;
        spotPrice = HyperdriveMath.calculateSpotPrice(
            effectiveShareReserves,
            _marketState.bondReserves,
            _initialVaultSharePrice,
            _timeStretch
        );

        // Calculate the fees charged to the user (curveFee) and the portion
        // of those fees that are paid to governance (governanceCurveFee).
        (curveFee, , governanceCurveFee, ) = _calculateFeesGivenBonds(
            _bondAmount,
            ONE, // shorts are opened at the beginning of the term
            spotPrice,
            _vaultSharePrice
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

        // NOTE: Round up to overestimate the base deposit.
        //
        // The trader will need to deposit capital to pay for the fixed rate,
        // the curve fee, the flat fee, and any back-paid interest that will be
        // received back upon closing the trade. If negative interest has
        // accrued during the current checkpoint, we set the close vault share
        // price to equal the open vault share price. This ensures that shorts
        // don't benefit from negative interest that accrued during the current
        // checkpoint.
        uint256 vaultSharePrice = _vaultSharePrice; // avoid stack-too-deep
        baseDeposit = HyperdriveMath
            .calculateShortProceedsUp(
                _bondAmount,
                // NOTE: We subtract the governance fee back to the share
                // reserves delta here because the trader will need to provide
                // this in their deposit.
                shareReservesDelta - governanceCurveFee,
                _openVaultSharePrice,
                vaultSharePrice.max(_openVaultSharePrice),
                vaultSharePrice,
                _flatFee
            )
            .mulUp(_vaultSharePrice);

        return (baseDeposit, shareReservesDelta, governanceCurveFee, spotPrice);
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      closing a short. This calculation includes trading fees.
    /// @param _bondAmount The amount of bonds being purchased to close the
    ///        short.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _maturityTime The maturity time of the short position.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return shareProceeds The proceeds in shares of closing the short.
    /// @return shareReservesDelta The shares added to the reserves.
    /// @return shareAdjustmentDelta The change in the share adjustment.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateCloseShort(
        uint256 _bondAmount,
        uint256 _vaultSharePrice,
        uint256 _maturityTime
    )
        internal
        view
        returns (
            uint256 bondReservesDelta,
            uint256 shareProceeds,
            uint256 shareReservesDelta,
            int256 shareAdjustmentDelta,
            uint256 totalGovernanceFee,
            uint256 spotPrice
        )
    {
        // Calculate the effect that closing the short should have on the pool's
        // reserves as well as the amount of shares the trader pays to buy the
        // bonds that they shorted back at the market price.
        uint256 shareCurveDelta;
        uint256 effectiveShareReserves = _effectiveShareReserves();
        {
            // Calculate the effect that closing the short should have on the
            // pool's reserves as well as the amount of shares the trader needs
            // to pay to purchase the shorted bonds at the market price.
            //
            // NOTE: We calculate the time remaining from the latest checkpoint
            // to ensure that opening/closing a position doesn't result in
            // immediate profit.
            uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
            uint256 bondAmount = _bondAmount; // Avoid stack too deep.
            uint256 vaultSharePrice = _vaultSharePrice; // Avoid stack too deep.
            (
                shareCurveDelta,
                bondReservesDelta,
                shareReservesDelta
            ) = HyperdriveMath.calculateCloseShort(
                effectiveShareReserves,
                _marketState.bondReserves,
                bondAmount,
                timeRemaining,
                _timeStretch,
                vaultSharePrice,
                _initialVaultSharePrice
            );

            // Ensure that the trader didn't purchase bonds at a negative interest
            // rate after accounting for fees.
            spotPrice = HyperdriveMath.calculateSpotPrice(
                effectiveShareReserves,
                _marketState.bondReserves,
                _initialVaultSharePrice,
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
                Errors.throwInsufficientLiquidityError();
            }

            // Calculate the fees charged to the user (curveFee and
            // flatFee) and the portion of those fees that are paid to
            // governance (totalGovernanceFee).
            uint256 curveFee;
            uint256 flatFee;
            uint256 governanceCurveFee;
            (
                curveFee,
                flatFee,
                governanceCurveFee,
                totalGovernanceFee
            ) = _calculateFeesGivenBonds(
                bondAmount,
                timeRemaining,
                spotPrice,
                vaultSharePrice
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
            uint256 openVaultSharePrice = _checkpoints[
                _maturityTime - _positionDuration
            ].vaultSharePrice;
            uint256 closeVaultSharePrice = block.timestamp < _maturityTime
                ? _vaultSharePrice
                : _checkpoints[_maturityTime].vaultSharePrice;

            // NOTE: Round down to underestimate the short proceeds.
            //
            // Calculate the share proceeds owed to the short. We calculate this
            // before scaling the share payment for negative interest. Shorts
            // are responsible for paying for 100% of the negative interest, so
            // they aren't benefited when the payment to LPs is decreased due to
            // negative interest. Similarly, the governance fee is included in
            // the share payment. The LPs don't receive the governance fee, but
            // the short is responsible for paying it.
            uint256 vaultSharePrice = _vaultSharePrice; // Avoid stack too deep.
            shareProceeds = HyperdriveMath.calculateShortProceedsDown(
                _bondAmount,
                shareReservesDelta,
                openVaultSharePrice,
                closeVaultSharePrice,
                vaultSharePrice,
                _flatFee
            );

            // The governance fee isn't included in the share payment that is
            // added to the share reserves. We remove it here to simplify the
            // accounting updates.
            shareReservesDelta -= totalGovernanceFee;

            // Ensure that the ending spot price is less than 1.
            if (
                HyperdriveMath.calculateSpotPrice(
                    effectiveShareReserves + shareCurveDelta,
                    _marketState.bondReserves - bondReservesDelta,
                    _initialVaultSharePrice,
                    _timeStretch
                ) > ONE
            ) {
                Errors.throwInsufficientLiquidityError();
            }

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
                openVaultSharePrice,
                closeVaultSharePrice,
                false
            );
        }

        return (
            bondReservesDelta,
            shareProceeds,
            shareReservesDelta,
            shareAdjustmentDelta,
            totalGovernanceFee,
            spotPrice
        );
    }
}
