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
/// @title HyperdriveLong
/// @notice Implements the long accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveLong is IHyperdriveEvents, HyperdriveLP {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @dev Opens a long position.
    /// @param _amount The amount of capital provided to open the long. The
    ///        units of this quantity are either base or vault shares, depending
    ///        on the value of `_options.asBase`.
    /// @param _minOutput The minimum number of bonds to receive.
    /// @param _minVaultSharePrice The minimum vault share price at which to
    ///        open the long. This allows traders to protect themselves from
    ///        opening a long in a checkpoint where negative interest has
    ///        accrued.
    /// @param _options The options that configure how the trade is settled.
    /// @return maturityTime The maturity time of the bonds.
    /// @return bondProceeds The amount of bonds the user received.
    function _openLong(
        uint256 _amount,
        uint256 _minOutput,
        uint256 _minVaultSharePrice,
        IHyperdrive.Options calldata _options
    )
        internal
        nonReentrant
        isNotPaused
        returns (uint256 maturityTime, uint256 bondProceeds)
    {
        // Check that the message value is valid.
        _checkMessageValue();

        // Check that the provided options are valid.
        _checkOptions(_options);

        // Deposit the user's input amount.
        (uint256 sharesDeposited, uint256 vaultSharePrice) = _deposit(
            _amount,
            _options
        );

        // Enforce the minimum user outputs and the minimum vault share price.
        //
        // NOTE: We use the value that is returned from the deposit to check
        // against the minimum transaction amount because in the event of
        // slippage on the deposit, we want the inputs to the state updates to
        // respect the minimum transaction amount requirements.
        //
        // NOTE: Round down to underestimate the base deposit. This makes the
        //       minimum transaction amount check more conservative.
        uint256 baseDeposited = sharesDeposited.mulDown(vaultSharePrice);
        if (baseDeposited < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }
        if (vaultSharePrice < _minVaultSharePrice) {
            revert IHyperdrive.MinimumSharePrice();
        }

        // Perform a checkpoint.
        uint256 latestCheckpoint = _latestCheckpoint();
        _applyCheckpoint(
            latestCheckpoint,
            vaultSharePrice,
            LPMath.SHARE_PROCEEDS_MAX_ITERATIONS,
            true
        );

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds purchased to the beginning of the checkpoint.
        // Note: All state deltas are derived from the output of the
        // deposit function.
        uint256 shareReservesDelta;
        uint256 totalGovernanceFee;
        uint256 spotPrice;
        (
            shareReservesDelta,
            bondProceeds,
            totalGovernanceFee,
            spotPrice
        ) = _calculateOpenLong(sharesDeposited, vaultSharePrice);

        // Enforce the minimum user outputs.
        if (bondProceeds < _minOutput) {
            revert IHyperdrive.OutputLimit();
        }

        // Attribute the governance fee.
        _governanceFeesAccrued += totalGovernanceFee;

        // Update the weighted spot price.
        _updateWeightedSpotPrice(latestCheckpoint, block.timestamp, spotPrice);

        // Apply the open long to the state.
        maturityTime = latestCheckpoint + _positionDuration;
        _applyOpenLong(
            shareReservesDelta,
            bondProceeds,
            vaultSharePrice,
            maturityTime
        );

        // Mint the bonds to the trader with an ID of the maturity time.
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );
        _mint(assetId, _options.destination, bondProceeds);

        // Emit an OpenLong event.
        uint256 amount = _amount; // Avoid stack too deep error.
        uint256 maturityTime_ = maturityTime; // Avoid stack too deep error.
        uint256 bondProceeds_ = bondProceeds; // Avoid stack too deep error.
        uint256 vaultSharePrice_ = vaultSharePrice; // Avoid stack too deep error.
        IHyperdrive.Options calldata options = _options; // Avoid stack too deep error.
        emit OpenLong(
            options.destination,
            assetId,
            maturityTime_,
            amount,
            vaultSharePrice_,
            options.asBase,
            bondProceeds_,
            options.extraData
        );

        return (maturityTime, bondProceeds_);
    }

    /// @dev Closes a long position with a specified maturity time.
    /// @param _maturityTime The maturity time of the long.
    /// @param _bondAmount The amount of longs to close.
    /// @param _minOutput The minimum proceeds the trader will accept. The units
    ///        of this quantity are either base or vault shares, depending on
    ///        the value of `_options.asBase`.
    /// @param _options The options that configure how the trade is settled.
    /// @return The proceeds the user receives. The units of this quantity are
    ///         either base or vault shares, depending on the value of
    ///         `_options.asBase`.
    function _closeLong(
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

        // If the long hasn't matured, we checkpoint the latest checkpoint.
        // Otherwise, we perform a checkpoint at the time the long matured.
        // This ensures the long and all of the other positions in the
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

        // Burn the longs that are being closed.
        _burn(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _maturityTime),
            msg.sender,
            _bondAmount
        );

        // Calculate the pool and user deltas using the trading function.
        // Note: All state deltas are derived from external function inputs.
        (
            uint256 bondReservesDelta,
            uint256 shareProceeds,
            uint256 shareReservesDelta,
            int256 shareAdjustmentDelta,
            uint256 totalGovernanceFee,
            uint256 spotPrice
        ) = _calculateCloseLong(_bondAmount, vaultSharePrice, _maturityTime);

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the long to the reserves and pay out the
        // withdrawal pool if necessary.
        uint256 maturityTime = _maturityTime; // Avoid stack too deep error.
        if (block.timestamp < _maturityTime) {
            // Attribute the governance fee.
            _governanceFeesAccrued += totalGovernanceFee;

            // Update the weighted spot price.
            _updateWeightedSpotPrice(
                _latestCheckpoint(),
                block.timestamp,
                spotPrice
            );

            // Apply the close long to the state.
            _applyCloseLong(
                _bondAmount,
                bondReservesDelta,
                shareReservesDelta,
                shareAdjustmentDelta,
                maturityTime
            );

            // Update the global long exposure. Since we're closing a long, the
            // number of non-netted longs decreases by the bond amount.
            int256 nonNettedLongs = _nonNettedLongs(maturityTime);
            _updateLongExposure(
                nonNettedLongs + _bondAmount.toInt256(),
                nonNettedLongs
            );

            // Closing longs decreases the share reserves. When the longs that
            // are being closed are partially or fully netted out, it's possible
            // that fully closing the long could make the system insolvent.
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

        // Withdraw the profit to the trader.
        uint256 proceeds = _withdraw(shareProceeds, vaultSharePrice, _options);

        // Enforce the minimum user outputs.
        //
        // NOTE: We use the value that is returned from the withdraw to check
        // against the minOutput because in the event of slippage on the
        // withdraw, we want it to be caught be the minOutput check.
        if (proceeds < _minOutput) {
            revert IHyperdrive.OutputLimit();
        }

        // Emit a CloseLong event.
        uint256 bondAmount = _bondAmount; // Avoid stack too deep error.
        uint256 vaultSharePrice_ = vaultSharePrice; // Avoid stack too deep error.
        IHyperdrive.Options calldata options = _options; // Avoid stack too deep error.
        emit CloseLong(
            msg.sender, // trader
            options.destination, // destination
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            maturityTime,
            proceeds,
            vaultSharePrice_,
            options.asBase,
            bondAmount,
            options.extraData
        );

        return proceeds;
    }

    /// @dev Applies an open long to the state. This includes updating the
    ///      reserves and maintaining the reserve invariants.
    /// @param _shareReservesDelta The amount of shares paid to the curve.
    /// @param _bondReservesDelta The amount of bonds sold by the curve.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _maturityTime The maturity time of the long.
    function _applyOpenLong(
        uint256 _shareReservesDelta,
        uint256 _bondReservesDelta,
        uint256 _vaultSharePrice,
        uint256 _maturityTime
    ) internal {
        // Update the average maturity time of long positions.
        uint128 longsOutstanding_ = _marketState.longsOutstanding;
        _marketState.longAverageMaturityTime = uint256(
            _marketState.longAverageMaturityTime
        )
            .updateWeightedAverage(
                longsOutstanding_,
                _maturityTime * ONE, // scale up to fixed point scale
                _bondReservesDelta,
                true
            )
            .toUint128();

        // Apply the trading deltas to the reserves and update the amount of
        // longs outstanding.
        _marketState.shareReserves += _shareReservesDelta.toUint128();
        _marketState.bondReserves -= _bondReservesDelta.toUint128();
        longsOutstanding_ += _bondReservesDelta.toUint128();
        _marketState.longsOutstanding = longsOutstanding_;

        // Update the global long exposure. Since we're opening a long, the
        // number of non-netted longs increases by the bond amount.
        int256 nonNettedLongs = _nonNettedLongs(_maturityTime);
        _updateLongExposure(
            nonNettedLongs,
            nonNettedLongs + _bondReservesDelta.toInt256()
        );

        // We need to check solvency because longs increase the system's exposure.
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

    /// @dev Applies the trading deltas from a closed long to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of longs that were closed.
    /// @param _bondReservesDelta The bonds to add to the reserves.
    /// @param _shareReservesDelta The shares to remove from the reserves.
    /// @param _shareAdjustmentDelta The amount to decrease the share adjustment.
    /// @param _maturityTime The maturity time of the long.
    function _applyCloseLong(
        uint256 _bondAmount,
        uint256 _bondReservesDelta,
        uint256 _shareReservesDelta,
        int256 _shareAdjustmentDelta,
        uint256 _maturityTime
    ) internal {
        // The share reserves are decreased in this operation, so we need to
        // verify the invariant that z >= z_min is satisfied.
        uint256 shareReserves = _marketState.shareReserves;
        if (
            shareReserves < _shareReservesDelta ||
            shareReserves - _shareReservesDelta < _minimumShareReserves
        ) {
            Errors.throwInsufficientLiquidityError();
        }
        unchecked {
            shareReserves -= _shareReservesDelta;
        }

        // If the effective share reserves are decreasing, then we need to
        // verify that z - zeta >= z_min is satisfied.
        //
        // NOTE: Avoiding this check when the effective share reserves aren't
        // decreasing is important since `removeLiquidity` can result in an
        // effective share reserves less than the minimum share reserves, and
        // it's important that this doesn't result in failed checkpoints.
        int256 shareAdjustment = _marketState.shareAdjustment;
        shareAdjustment -= _shareAdjustmentDelta;
        if (
            _shareReservesDelta.toInt256() > _shareAdjustmentDelta &&
            HyperdriveMath.calculateEffectiveShareReserves(
                shareReserves,
                shareAdjustment
            ) <
            _minimumShareReserves
        ) {
            Errors.throwInsufficientLiquidityError();
        }

        // Update the long average maturity time.
        uint256 longsOutstanding = _marketState.longsOutstanding;
        _marketState.longAverageMaturityTime = uint256(
            _marketState.longAverageMaturityTime
        )
            .updateWeightedAverage(
                longsOutstanding,
                _maturityTime * ONE, // scale up to fixed point scale
                _bondAmount,
                false
            )
            .toUint128();

        // Reduce the amount of outstanding longs.
        longsOutstanding -= _bondAmount;
        _marketState.longsOutstanding = longsOutstanding.toUint128();

        // Apply the updates from the curve and flat components of the trade to
        // the reserves. The share proceeds are added to the share reserves
        // since the LPs are buying bonds for shares.  The bond reserves are
        // increased by the curve component to decrease the spot price. The
        // share adjustment is increased by the flat component of the share
        // reserves update so that we can translate the curve to hold the
        // pricing invariant under the flat update.
        _marketState.shareReserves = shareReserves.toUint128();
        _marketState.shareAdjustment = shareAdjustment.toInt128();
        _marketState.bondReserves += _bondReservesDelta.toUint128();
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      opening a long. This calculation includes trading fees.
    /// @param _shareAmount The amount of shares being paid to open the long.
    /// @param _vaultSharePrice The current vault share price.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return totalGovernanceFee The governance fee in shares.
    /// @return spotPrice The pool's current spot price.
    function _calculateOpenLong(
        uint256 _shareAmount,
        uint256 _vaultSharePrice
    )
        internal
        view
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 totalGovernanceFee,
            uint256 spotPrice
        )
    {
        // Calculate the effect that opening the long should have on the pool's
        // reserves as well as the amount of bond the trader receives.
        uint256 effectiveShareReserves = _effectiveShareReserves();
        bondReservesDelta = HyperdriveMath.calculateOpenLong(
            effectiveShareReserves,
            _marketState.bondReserves,
            _shareAmount, // amountIn
            _timeStretch,
            _vaultSharePrice,
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
                _shareAmount,
                bondReservesDelta,
                HyperdriveMath.calculateOpenLongMaxSpotPrice(
                    spotPrice,
                    _curveFee,
                    _flatFee
                )
            )
        ) {
            Errors.throwInsufficientLiquidityError();
        }

        // Calculate the fees paid to open the long and apply these fees to the
        // reserves deltas.
        (
            shareReservesDelta,
            bondReservesDelta,
            totalGovernanceFee
        ) = _calculateOpenLongFees(
            _shareAmount,
            bondReservesDelta,
            _vaultSharePrice,
            spotPrice
        );

        // Ensure that the ending spot price is less than or equal to one.
        // Despite the fact that the earlier negative interest check should
        // imply this, we perform this check out of an abundance of caution
        // since the `pow` function is known to not be monotonic.
        if (
            HyperdriveMath.calculateSpotPrice(
                effectiveShareReserves + shareReservesDelta,
                _marketState.bondReserves - bondReservesDelta,
                _initialVaultSharePrice,
                _timeStretch
            ) > ONE
        ) {
            Errors.throwInsufficientLiquidityError();
        }

        return (
            shareReservesDelta,
            bondReservesDelta,
            totalGovernanceFee,
            spotPrice
        );
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      closing a long. This calculation includes trading fees.
    /// @param _bondAmount The amount of bonds being purchased to close the short.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _maturityTime The maturity time of the short position.
    /// @return bondReservesDelta The bonds added to the reserves.
    /// @return shareProceeds The proceeds in shares of selling the bonds.
    /// @return shareReservesDelta The shares removed from the reserves.
    /// @return shareAdjustmentDelta The change in the share adjustment.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateCloseLong(
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
        // Calculate the effect that closing the long should have on the pool's
        // reserves as well as the amount of shares the trader receives for
        // selling their bonds.
        uint256 shareCurveDelta;
        {
            // Calculate the effect that closing the long should have on the
            // pool's reserves as well as the amount of shares the trader
            // receives for selling the bonds at the market price.
            //
            // NOTE: We calculate the time remaining from the latest checkpoint
            // to ensure that opening/closing a position doesn't result in
            // immediate profit.
            uint256 effectiveShareReserves = _effectiveShareReserves();
            uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
            uint256 vaultSharePrice = _vaultSharePrice; // avoid stack-too-deep
            uint256 bondAmount = _bondAmount; // avoid stack-too-deep
            (shareCurveDelta, bondReservesDelta, shareProceeds) = HyperdriveMath
                .calculateCloseLong(
                    effectiveShareReserves,
                    _marketState.bondReserves,
                    bondAmount,
                    timeRemaining,
                    _timeStretch,
                    vaultSharePrice,
                    _initialVaultSharePrice
                );

            // Calculate the fees that should be paid by the trader. The trader
            // pays a fee on the curve and flat parts of the trade. Most of the
            // fees go the LPs, but a portion goes to governance.
            uint256 curveFee;
            uint256 governanceCurveFee;
            uint256 flatFee;
            spotPrice = HyperdriveMath.calculateSpotPrice(
                effectiveShareReserves,
                _marketState.bondReserves,
                _initialVaultSharePrice,
                _timeStretch
            );
            (
                curveFee, // shares
                flatFee, // shares
                governanceCurveFee, // shares
                totalGovernanceFee // shares
            ) = _calculateFeesGivenBonds(
                bondAmount,
                timeRemaining,
                spotPrice,
                vaultSharePrice
            );

            // The curve fee (shares) is paid to the LPs, so we subtract it from
            // the share curve delta (shares) to prevent it from being debited
            // from the reserves when the state is updated. The governance curve
            // fee (shares) is paid to governance, so we add it back to the
            // share curve delta (shares) to ensure that the governance fee
            // isn't included in the share adjustment.
            shareCurveDelta -= (curveFee - governanceCurveFee);

            // The trader pays the curve fee (shares) and flat fee (shares) to
            // the pool, so we debit them from the trader's share proceeds
            // (shares).
            shareProceeds -= curveFee + flatFee;

            // We applied the full curve and flat fees to the share proceeds,
            // which reduce the trader's proceeds. To calculate the payment that
            // is applied to the share reserves (and is effectively paid by the
            // LPs), we need to add governance's portion of these fees to the
            // share proceeds.
            shareReservesDelta = shareProceeds + totalGovernanceFee;
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
            // NOTE: We use the vault share price from the beginning of the
            // checkpoint as the open vault share price. This means that a
            // trader that opens a long in a checkpoint that has negative
            // interest accrued will be penalized for the negative interest when
            // they try to close their position. The `_minVaultSharePrice`
            // parameter allows traders to protect themselves from this edge
            // case.
            _checkpoints[_maturityTime - _positionDuration].vaultSharePrice, // open vault share price
            block.timestamp < _maturityTime
                ? _vaultSharePrice
                : _checkpoints[_maturityTime].vaultSharePrice, // close vault share price
            true
        );

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
