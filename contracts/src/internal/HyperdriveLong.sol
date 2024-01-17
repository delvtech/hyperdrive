// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";
import { SafeCast } from "../libraries/SafeCast.sol";
import { HyperdriveLP } from "./HyperdriveLP.sol";

/// @author DELV
/// @title HyperdriveLong
/// @notice Implements the long accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveLong is HyperdriveLP {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @dev Opens a long position.
    /// @param _amount The amount to open a long with.
    /// @param _minOutput The minimum number of bonds to receive.
    /// @param _minVaultSharePrice The minimum vault share price at which to
    ///        open the long. This allows traders to protect themselves from
    ///        opening a long in a checkpoint where negative interest has
    ///        accrued.
    /// @param _options The options that configure how the trade is settled.
    /// @return maturityTime The maturity time of the bonds.
    /// @return bondProceeds The amount of bonds the user received
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

        // Deposit the user's input amount.
        (uint256 sharesDeposited, uint256 vaultSharePrice) = _deposit(
            _amount,
            _options
        );

        // Enforce the minimum user outputs and the mininum vault share price.
        //
        // NOTE: We use the value that is returned from the deposit to check
        // against the minimum transaction amount because in the event of
        // slippage on the deposit, we want the inputs to the state updates to
        // respect the minimum transaction amount requirements.
        uint256 baseDeposited = sharesDeposited.mulDown(vaultSharePrice);
        if (baseDeposited < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }
        if (vaultSharePrice < _minVaultSharePrice) {
            revert IHyperdrive.MinimumSharePrice();
        }

        // Perform a checkpoint.
        uint256 latestCheckpoint = _latestCheckpoint();
        _applyCheckpoint(latestCheckpoint, vaultSharePrice);

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds purchased to the beginning of the checkpoint.
        // Note: All state deltas are derived from the output of the
        // deposit function.
        uint256 shareReservesDelta;
        uint256 bondReservesDelta;
        uint256 totalGovernanceFee;
        (
            shareReservesDelta,
            bondReservesDelta,
            bondProceeds,
            totalGovernanceFee
        ) = _calculateOpenLong(sharesDeposited, vaultSharePrice);

        // Enforce the minimum user outputs.
        if (_minOutput > bondProceeds) {
            revert IHyperdrive.OutputLimit();
        }

        // Attribute the governance fee.
        _governanceFeesAccrued += totalGovernanceFee;

        // Apply the open long to the state.
        maturityTime = latestCheckpoint + _positionDuration;
        _applyOpenLong(
            shareReservesDelta,
            bondProceeds,
            bondReservesDelta,
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
        IHyperdrive.Options calldata options = _options; // Avoid stack too deep error.
        uint256 _bondProceeds = bondProceeds; // Avoid stack too deep error.
        emit OpenLong(
            _options.destination,
            assetId,
            maturityTime,
            _convertToBaseFromOption(amount, vaultSharePrice, options),
            vaultSharePrice,
            _bondProceeds
        );

        return (maturityTime, _bondProceeds);
    }

    /// @dev Closes a long position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of longs to close.
    /// @param _minOutput The minimum amount of base the trader will accept.
    /// @param _options The options that configure how the trade is settled.
    /// @return The amount of underlying the user receives.
    function _closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) internal nonReentrant returns (uint256) {
        if (_bondAmount < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // Perform a checkpoint at the maturity time. This ensures the long and
        // all of the other positions in the checkpoint are closed. This will
        // have no effect if the maturity time is in the future.
        uint256 vaultSharePrice = _pricePerVaultShare();
        _applyCheckpoint(_maturityTime, vaultSharePrice);

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
            uint256 totalGovernanceFee
        ) = _calculateCloseLong(_bondAmount, vaultSharePrice, _maturityTime);

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the long to the reserves and pay out the
        // withdrawal pool if necessary.
        uint256 maturityTime = _maturityTime; // Avoid stack too deep error.
        if (block.timestamp < _maturityTime) {
            // Attribute the governance fee.
            _governanceFeesAccrued += totalGovernanceFee;
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
                nonNettedLongs + int256(_bondAmount),
                nonNettedLongs
            );

            // Distribute the excess idle to the withdrawal pool.
            _distributeExcessIdle(vaultSharePrice);
        } else {
            // Apply the zombie close to the state and adjust the share proceeds
            // to account for negative interest that might have accrued to the
            // zombie share reserves.
            shareProceeds = _applyZombieClose(shareProceeds, vaultSharePrice);
        }

        // Withdraw the profit to the trader.
        uint256 proceeds = _withdraw(shareProceeds, _options);

        // Enforce min user outputs.
        // Note: We use the value that is returned from the
        // withdraw to check against the minOutput because
        // in the event of slippage on the withdraw, we want
        // it to be caught be the minOutput check.
        uint256 baseProceeds = _convertToBaseFromOption(
            proceeds,
            vaultSharePrice,
            _options
        );
        if (_minOutput > baseProceeds) {
            revert IHyperdrive.OutputLimit();
        }

        // Emit a CloseLong event.
        uint256 bondAmount = _bondAmount; // Avoid stack too deep error.
        emit CloseLong(
            _options.destination,
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            maturityTime,
            baseProceeds,
            vaultSharePrice,
            bondAmount
        );

        return proceeds;
    }

    /// @dev Applies an open long to the state. This includes updating the
    ///      reserves and maintaining the reserve invariants.
    /// @param _shareReservesDelta The amount of shares paid to the curve.
    /// @param _bondProceeds The amount of bonds purchased by the trader.
    /// @param _bondReservesDelta The amount of bonds sold by the curve.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _maturityTime The maturity time of the long.
    function _applyOpenLong(
        uint256 _shareReservesDelta,
        uint256 _bondProceeds,
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
                uint256(longsOutstanding_),
                _maturityTime * 1e18, // scale up to fixed point scale
                _bondProceeds,
                true
            )
            .toUint128();

        // Apply the trading deltas to the reserves and update the amount of
        // longs outstanding.
        _marketState.shareReserves += _shareReservesDelta.toUint128();
        _marketState.bondReserves -= _bondReservesDelta.toUint128();
        longsOutstanding_ += _bondProceeds.toUint128();
        _marketState.longsOutstanding = longsOutstanding_;

        // Update the global long exposure. Since we're opening a long, the
        // number of non-netted longs increases by the bond amount.
        int256 nonNettedLongs = _nonNettedLongs(_maturityTime);
        _updateLongExposure(
            nonNettedLongs,
            nonNettedLongs + int256(_bondProceeds)
        );

        // We need to check solvency because longs increase the system's exposure.
        if (!_isSolvent(_vaultSharePrice)) {
            revert IHyperdrive.InsufficientLiquidity();
        }

        // Distribute the excess idle to the withdrawal pool.
        _distributeExcessIdle(_vaultSharePrice);
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
        {
            uint128 longsOutstanding_ = _marketState.longsOutstanding;

            // Update the long average maturity time.
            _marketState.longAverageMaturityTime = uint256(
                _marketState.longAverageMaturityTime
            )
                .updateWeightedAverage(
                    longsOutstanding_,
                    _maturityTime * 1e18, // scale up to fixed point scale
                    _bondAmount,
                    false
                )
                .toUint128();

            // Reduce the amount of outstanding longs.
            _marketState.longsOutstanding =
                longsOutstanding_ -
                _bondAmount.toUint128();
        }

        // Apply the updates from the curve and flat components of the trade to
        // the reserves. The share proceeds are added to the share reserves
        // since the LPs are buying bonds for shares.  The bond reserves are
        // increased by the curve component to decrease the spot price. The
        // share adjustment is increased by the flat component of the share
        // reserves update so that we can translate the curve to hold the
        // pricing invariant under the flat update.
        _marketState.shareReserves -= _shareReservesDelta.toUint128();
        _marketState.shareAdjustment -= _shareAdjustmentDelta.toInt128();
        _marketState.bondReserves += _bondReservesDelta.toUint128();

        // TODO: We're not sure what causes the z >= zeta check to fail.
        // It may be unnecessary, but that needs to be proven before we can
        // remove it.
        //
        // The share reserves are decreased in this operation, so we need to
        // verify that our invariants that z >= z_min and z >= zeta
        // are satisfied.
        if (
            uint256(_marketState.shareReserves) < _minimumShareReserves ||
            int256(uint256(_marketState.shareReserves)) <
            _marketState.shareAdjustment
        ) {
            revert IHyperdrive.InvalidShareReserves();
        }
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      opening a long. This calculation includes trading fees.
    /// @param _shareAmount The amount of shares being paid to open the long.
    /// @param _vaultSharePrice The current vault share price.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return bondProceeds The proceeds in bonds.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateOpenLong(
        uint256 _shareAmount,
        uint256 _vaultSharePrice
    )
        internal
        view
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 bondProceeds,
            uint256 totalGovernanceFee
        )
    {
        // Calculate the effect that opening the long should have on the pool's
        // reserves as well as the amount of bond the trader receives.
        bondReservesDelta = HyperdriveMath.calculateOpenLong(
            _effectiveShareReserves(),
            _marketState.bondReserves,
            _shareAmount, // amountIn
            _timeStretch,
            _vaultSharePrice,
            _initialVaultSharePrice
        );

        // Ensure that the trader didn't purchase bonds at a negative interest
        // rate after accounting for fees.
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            _effectiveShareReserves(),
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
            revert IHyperdrive.NegativeInterest();
        }

        // Calculate the fees charged to the user (curveFee) and the portion
        // of those fees that are paid to governance (governanceCurveFee).
        (
            uint256 curveFee, // bonds
            uint256 governanceCurveFee // bonds
        ) = _calculateFeesGivenShares(
                _shareAmount,
                spotPrice,
                _vaultSharePrice
            );

        // Calculate the number of bonds the trader receives.
        // This is the amount of bonds the trader receives minus the fees.
        bondProceeds = bondReservesDelta - curveFee;

        // Calculate how many bonds to remove from the bondReserves.
        // The bondReservesDelta represents how many bonds to remove
        // This should be the number of bonds the trader receives plus
        // the number of bonds we need to pay to governance.
        // In other words, we want to keep the curveFee in the bondReserves;
        // however, since the governanceCurveFee will be paid from the
        // sharesReserves we don't need it removed from the bondReserves.
        // bondProceeds and governanceCurveFee are already in bonds so no
        // conversion is needed:
        //
        // bonds = bonds + bonds
        bondReservesDelta = bondProceeds + governanceCurveFee;

        // Calculate the fees owed to governance in shares. Open longs are
        // calculated entirely on the curve so the curve fee is the total
        // governance fee. In order to convert it to shares we need to multiply
        // it by the spot price and divide it by the vault share price:
        //
        // shares = (bonds * base/bonds) / (base/shares)
        // shares = bonds * shares/bonds
        // shares = shares
        totalGovernanceFee = governanceCurveFee.mulDivDown(
            spotPrice,
            _vaultSharePrice
        );

        // Calculate the number of shares to add to the shareReserves.
        // shareReservesDelta, _shareAmount and totalGovernanceFee
        // are all denominated in shares:
        //
        // shares = shares - shares
        shareReservesDelta = _shareAmount - totalGovernanceFee;

        return (
            shareReservesDelta,
            bondReservesDelta,
            bondProceeds,
            totalGovernanceFee
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
            uint256 totalGovernanceFee
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
            uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
            (shareCurveDelta, bondReservesDelta, shareProceeds) = HyperdriveMath
                .calculateCloseLong(
                    _effectiveShareReserves(),
                    _marketState.bondReserves,
                    _bondAmount,
                    timeRemaining,
                    _timeStretch,
                    _vaultSharePrice,
                    _initialVaultSharePrice
                );

            // Calculate the fees that should be paid by the trader. The trader
            // pays a fee on the curve and flat parts of the trade. Most of the
            // fees go the LPs, but a portion goes to governance.
            uint256 curveFee;
            uint256 flatFee;
            uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
                _effectiveShareReserves(),
                _marketState.bondReserves,
                _initialVaultSharePrice,
                _timeStretch
            );
            (
                curveFee, // shares
                flatFee, // shares
                ,
                totalGovernanceFee // shares
            ) = _calculateFeesGivenBonds(
                _bondAmount,
                timeRemaining,
                spotPrice,
                _vaultSharePrice
            );

            // The curve fee (shares) is paid to the LPs, so we subtract it from
            // the share curve delta (shares) to prevent it from being debited
            // from the reserves when the state is updated.
            shareCurveDelta -= curveFee;

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
    }
}
