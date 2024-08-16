/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { Errors } from "./Errors.sol";
import { FixedPointMath, ONE } from "./FixedPointMath.sol";
import { SafeCast } from "./SafeCast.sol";
import { YieldSpaceMath } from "./YieldSpaceMath.sol";

/// @author DELV
/// @title Hyperdrive
/// @notice Math for the Hyperdrive pricing model.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library HyperdriveMath {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;

    /// @dev Calculates the checkpoint time of a given timestamp.
    /// @param _timestamp The timestamp to use to calculate the checkpoint time.
    /// @param _checkpointDuration The checkpoint duration.
    /// @return The checkpoint time.
    function calculateCheckpointTime(
        uint256 _timestamp,
        uint256 _checkpointDuration
    ) internal pure returns (uint256) {
        return _timestamp - (_timestamp % _checkpointDuration);
    }

    /// @dev Calculates the time stretch parameter for the YieldSpace curve.
    ///      This parameter modifies the curvature in order to support a larger
    ///      or smaller range of APRs. The lower the time stretch, the flatter
    ///      the curve will be and the narrower the range of feasible APRs. The
    ///      higher the time stretch, the higher the curvature will be and the
    ///      wider the range of feasible APRs.
    /// @param _apr The target APR to use when calculating the time stretch.
    /// @param _positionDuration The position duration in seconds.
    /// @return The time stretch parameter.
    function calculateTimeStretch(
        uint256 _apr,
        uint256 _positionDuration
    ) internal pure returns (uint256) {
        // Calculate the benchmark time stretch. This time stretch is tuned for
        // a position duration of 1 year.
        uint256 timeStretch = uint256(5.24592e18).divDown(
            uint256(0.04665e18).mulDown(_apr * 100)
        );
        timeStretch = ONE.divDown(timeStretch);

        // We know that the following simultaneous equations hold:
        //
        // (1 + apr) * A ** timeStretch = 1
        //
        // and
        //
        // (1 + apr * (positionDuration / 365 days)) * A ** targetTimeStretch = 1
        //
        // where A is the reserve ratio. We can solve these equations for the
        // target time stretch as follows:
        //
        // targetTimeStretch = (
        //     ln(1 + apr * (positionDuration / 365 days)) /
        //     ln(1 + apr)
        // ) * timeStretch
        //
        // NOTE: Round down so that the output is an underestimate.
        return
            (
                uint256(
                    (ONE + _apr.mulDivDown(_positionDuration, 365 days))
                        .toInt256()
                        .ln()
                ).divDown(uint256((ONE + _apr).toInt256().ln()))
            ).mulDown(timeStretch);
    }

    /// @dev Calculates the APR implied by a price.
    /// @param _price The price to convert to an APR.
    /// @param _duration The term duration.
    /// @return The APR implied by the price.
    function calculateAPRFromPrice(
        uint256 _price,
        uint256 _duration
    ) internal pure returns (uint256) {
        // NOTE: Round down to underestimate the spot APR.
        return
            (ONE - _price).divDown(
                // NOTE: Round up since this is in the denominator.
                _price.mulDivUp(_duration, 365 days)
            );
    }

    /// @dev Calculates the spot price of bonds in terms of base. This
    ///      calculation underestimates the pool's spot price.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _initialVaultSharePrice The initial vault share price.
    /// @param _timeStretch The time stretch parameter.
    /// @return spotPrice The spot price of bonds in terms of base.
    function calculateSpotPrice(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _initialVaultSharePrice,
        uint256 _timeStretch
    ) internal pure returns (uint256 spotPrice) {
        // NOTE: Round down to underestimate the spot price.
        //
        // p = (y / (mu * (z - zeta))) ** -t_s
        //   = ((mu * (z - zeta)) / y) ** t_s
        spotPrice = _initialVaultSharePrice
            .mulDivDown(_effectiveShareReserves, _bondReserves)
            .pow(_timeStretch);
    }

    /// @dev Calculates the spot APR of the pool. This calculation
    ///      underestimates the pool's spot APR.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _initialVaultSharePrice The pool's initial vault share price.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @return apr The pool's spot APR.
    function calculateSpotAPR(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _initialVaultSharePrice,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 apr) {
        // NOTE: Round down to underestimate the spot APR.
        //
        // We are interested calculating the fixed APR for the pool. The
        // annualized rate is given by the following formula:
        //
        // r = (1 - p) / (p * t)
        //
        // where t = _positionDuration / 365.
        uint256 spotPrice = calculateSpotPrice(
            _effectiveShareReserves,
            _bondReserves,
            _initialVaultSharePrice,
            _timeStretch
        );
        return calculateAPRFromPrice(spotPrice, _positionDuration);
    }

    /// @dev Calculates the effective share reserves. The effective share
    ///      reserves are the share reserves minus the share adjustment or
    ///      z - zeta. We use the effective share reserves as the z-parameter
    ///      to the YieldSpace pricing model. The share adjustment is used to
    ///      hold the pricing mechanism invariant under the flat component of
    ///      flat+curve trades.
    /// @param _shareReserves The pool's share reserves.
    /// @param _shareAdjustment The pool's share adjustment.
    /// @return effectiveShareReserves The effective share reserves.
    function calculateEffectiveShareReserves(
        uint256 _shareReserves,
        int256 _shareAdjustment
    ) internal pure returns (uint256 effectiveShareReserves) {
        bool success;
        (effectiveShareReserves, success) = calculateEffectiveShareReservesSafe(
            _shareReserves,
            _shareAdjustment
        );
        if (!success) {
            Errors.throwInsufficientLiquidityError();
        }
    }

    /// @dev Calculates the effective share reserves. The effective share
    ///      reserves are the share reserves minus the share adjustment or
    ///      z - zeta. We use the effective share reserves as the z-parameter
    ///      to the YieldSpace pricing model. The share adjustment is used to
    ///      hold the pricing mechanism invariant under the flat component of
    ///      flat+curve trades.
    /// @param _shareReserves The pool's share reserves.
    /// @param _shareAdjustment The pool's share adjustment.
    /// @return The effective share reserves.
    /// @return A flag indicating if the calculation succeeded.
    function calculateEffectiveShareReservesSafe(
        uint256 _shareReserves,
        int256 _shareAdjustment
    ) internal pure returns (uint256, bool) {
        int256 effectiveShareReserves = _shareReserves.toInt256() -
            _shareAdjustment;
        if (effectiveShareReserves < 0) {
            return (0, false);
        }
        return (uint256(effectiveShareReserves), true);
    }

    /// @dev Calculates the proceeds in shares of closing a short position. This
    ///      takes into account the trading profits, the interest that was
    ///      earned by the short, the flat fee the short pays, and the amount of
    ///      margin that was released by closing the short. The math for the
    ///      short's proceeds in base is given by:
    ///
    ///      proceeds = (1 + flat_fee) * dy - c * dz + (c1 - c0) * (dy / c0)
    ///               = (1 + flat_fee) * dy - c * dz + (c1 / c0) * dy - dy
    ///               = (c1 / c0 + flat_fee) * dy - c * dz
    ///
    ///      We convert the proceeds to shares by dividing by the current vault
    ///      share price. In the event that the interest is negative and
    ///      outweighs the trading profits and margin released, the short's
    ///      proceeds are marked to zero.
    ///
    ///      This variant of the calculation overestimates the short proceeds.
    /// @param _bondAmount The amount of bonds underlying the closed short.
    /// @param _shareAmount The amount of shares that it costs to close the
    ///                     short.
    /// @param _openVaultSharePrice The vault share price at the short's open.
    /// @param _closeVaultSharePrice The vault share price at the short's close.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _flatFee The flat fee currently within the pool
    /// @return shareProceeds The short proceeds in shares.
    function calculateShortProceedsUp(
        uint256 _bondAmount,
        uint256 _shareAmount,
        uint256 _openVaultSharePrice,
        uint256 _closeVaultSharePrice,
        uint256 _vaultSharePrice,
        uint256 _flatFee
    ) internal pure returns (uint256 shareProceeds) {
        // NOTE: Round up to overestimate the short proceeds.
        //
        // The total value is the amount of shares that underlies the bonds that
        // were shorted. The bonds start by being backed 1:1 with base, and the
        // total value takes into account all of the interest that has accrued
        // since the short was opened.
        //
        // total_value = (c1 / (c0 * c)) * dy
        uint256 totalValue = _bondAmount
            .mulDivUp(_closeVaultSharePrice, _openVaultSharePrice)
            .divUp(_vaultSharePrice);

        // NOTE: Round up to overestimate the short proceeds.
        //
        // We increase the total value by the flat fee amount, because it is
        // included in the total amount of capital underlying the short.
        totalValue += _bondAmount.mulDivUp(_flatFee, _vaultSharePrice);

        // If the interest is more negative than the trading profits and margin
        // released, then the short proceeds are marked to zero. Otherwise, we
        // calculate the proceeds as the sum of the trading proceeds, the
        // interest proceeds, and the margin released.
        if (totalValue > _shareAmount) {
            // proceeds = (c1 / (c0 * c)) * dy - dz
            unchecked {
                shareProceeds = totalValue - _shareAmount;
            }
        }

        return shareProceeds;
    }

    /// @dev Calculates the proceeds in shares of closing a short position. This
    ///      takes into account the trading profits, the interest that was
    ///      earned by the short, the flat fee the short pays, and the amount of
    ///      margin that was released by closing the short. The math for the
    ///      short's proceeds in base is given by:
    ///
    ///      proceeds = (1 + flat_fee) * dy - c * dz + (c1 - c0) * (dy / c0)
    ///               = (1 + flat_fee) * dy - c * dz + (c1 / c0) * dy - dy
    ///               = (c1 / c0 + flat_fee) * dy - c * dz
    ///
    ///      We convert the proceeds to shares by dividing by the current vault
    ///      share price. In the event that the interest is negative and
    ///      outweighs the trading profits and margin released, the short's
    ///      proceeds are marked to zero.
    ///
    ///      This variant of the calculation underestimates the short proceeds.
    /// @param _bondAmount The amount of bonds underlying the closed short.
    /// @param _shareAmount The amount of shares that it costs to close the
    ///                     short.
    /// @param _openVaultSharePrice The vault share price at the short's open.
    /// @param _closeVaultSharePrice The vault share price at the short's close.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _flatFee The flat fee currently within the pool
    /// @return shareProceeds The short proceeds in shares.
    function calculateShortProceedsDown(
        uint256 _bondAmount,
        uint256 _shareAmount,
        uint256 _openVaultSharePrice,
        uint256 _closeVaultSharePrice,
        uint256 _vaultSharePrice,
        uint256 _flatFee
    ) internal pure returns (uint256 shareProceeds) {
        // NOTE: Round down to underestimate the short proceeds.
        //
        // The total value is the amount of shares that underlies the bonds that
        // were shorted. The bonds start by being backed 1:1 with base, and the
        // total value takes into account all of the interest that has accrued
        // since the short was opened.
        //
        // total_value = (c1 / (c0 * c)) * dy
        uint256 totalValue = _bondAmount
            .mulDivDown(_closeVaultSharePrice, _openVaultSharePrice)
            .divDown(_vaultSharePrice);

        // NOTE: Round down to underestimate the short proceeds.
        //
        // We increase the total value by the flat fee amount, because it is
        // included in the total amount of capital underlying the short.
        totalValue += _bondAmount.mulDivDown(_flatFee, _vaultSharePrice);

        // If the interest is more negative than the trading profits and margin
        // released, then the short proceeds are marked to zero. Otherwise, we
        // calculate the proceeds as the sum of the trading proceeds, the
        // interest proceeds, and the margin released.
        if (totalValue > _shareAmount) {
            // proceeds = (c1 / (c0 * c)) * dy - dz
            unchecked {
                shareProceeds = totalValue - _shareAmount;
            }
        }

        return shareProceeds;
    }

    /// @dev Since traders pay a curve fee when they open longs on Hyperdrive,
    ///      it is possible for traders to receive a negative interest rate even
    ///      if curve's spot price is less than or equal to 1.
    ///
    ///      Given the curve fee `phi_c` and the starting spot price `p_0`, the
    ///      maximum spot price is given by:
    ///
    ///      p_max = (1 - phi_f) / (1 + phi_c * (1 / p_0 - 1) * (1 - phi_f))
    ///
    ///      We underestimate the maximum spot price to be conservative.
    /// @param _startingSpotPrice The spot price at the start of the trade.
    /// @param _curveFee The curve fee.
    /// @param _flatFee The flat fee.
    /// @return The maximum spot price.
    function calculateOpenLongMaxSpotPrice(
        uint256 _startingSpotPrice,
        uint256 _curveFee,
        uint256 _flatFee
    ) internal pure returns (uint256) {
        // NOTE: Round down to underestimate the maximum spot price.
        return
            (ONE - _flatFee).divDown(
                // NOTE: Round up since this is in the denominator.
                ONE +
                    _curveFee.mulUp(ONE.divUp(_startingSpotPrice) - ONE).mulUp(
                        ONE - _flatFee
                    )
            );
    }

    /// @dev Since traders pay a curve fee when they close shorts on Hyperdrive,
    ///      it is possible for traders to receive a negative interest rate even
    ///      if curve's spot price is less than or equal to 1.
    ///
    ///      Given the curve fee `phi_c` and the starting spot price `p_0`, the
    ///      maximum spot price is given by:
    ///
    ///      p_max = 1 - phi_c * (1 - p_0)
    ///
    ///      We underestimate the maximum spot price to be conservative.
    /// @param _startingSpotPrice The spot price at the start of the trade.
    /// @param _curveFee The curve fee.
    /// @return The maximum spot price.
    function calculateCloseShortMaxSpotPrice(
        uint256 _startingSpotPrice,
        uint256 _curveFee
    ) internal pure returns (uint256) {
        // Round the rhs down to underestimate the maximum spot price.
        return ONE - _curveFee.mulUp(ONE - _startingSpotPrice);
    }

    /// @dev Calculates the number of bonds a user will receive when opening a
    ///      long position.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _shareAmount The amount of shares the user is depositing.
    /// @param _timeStretch The time stretch parameter.
    /// @param _vaultSharePrice The vault share price.
    /// @param _initialVaultSharePrice The initial vault share price.
    /// @return bondReservesDelta The bonds paid by the reserves in the trade.
    function calculateOpenLong(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _shareAmount,
        uint256 _timeStretch,
        uint256 _vaultSharePrice,
        uint256 _initialVaultSharePrice
    ) internal pure returns (uint256) {
        // NOTE: We underestimate the trader's bond proceeds to avoid sandwich
        // attacks.
        return
            YieldSpaceMath.calculateBondsOutGivenSharesInDown(
                _effectiveShareReserves,
                _bondReserves,
                _shareAmount,
                // NOTE: Since the bonds traded on the curve are newly minted,
                // we use a time remaining of 1. This means that we can use
                // `_timeStretch = t * _timeStretch`.
                ONE - _timeStretch,
                _vaultSharePrice,
                _initialVaultSharePrice
            );
    }

    /// @dev Calculates the amount of shares a user will receive when closing a
    ///      long position.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _amountIn The amount of bonds the user is closing.
    /// @param _normalizedTimeRemaining The normalized time remaining of the
    ///        position.
    /// @param _timeStretch The time stretch parameter.
    /// @param _vaultSharePrice The vault share price.
    /// @param _initialVaultSharePrice The vault share price when the pool was
    ///        deployed.
    /// @return shareCurveDelta The shares paid by the reserves in the trade.
    /// @return bondCurveDelta The bonds paid to the reserves in the trade.
    /// @return shareProceeds The shares that the user will receive.
    function calculateCloseLong(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _vaultSharePrice,
        uint256 _initialVaultSharePrice
    )
        internal
        pure
        returns (
            uint256 shareCurveDelta,
            uint256 bondCurveDelta,
            uint256 shareProceeds
        )
    {
        // NOTE: We underestimate the trader's share proceeds to avoid sandwich
        // attacks.
        //
        // We consider `(1 - timeRemaining) * amountIn` of the bonds to be fully
        // matured and timeRemaining * amountIn of the bonds to be newly
        // minted. The fully matured bonds are redeemed one-to-one to base
        // (our result is given in shares, so we divide the one-to-one
        // redemption by the vault share price) and the newly minted bonds are
        // traded on a YieldSpace curve configured to `timeRemaining = 1`.
        shareProceeds = _amountIn.mulDivDown(
            ONE - _normalizedTimeRemaining,
            _vaultSharePrice
        );
        if (_normalizedTimeRemaining > 0) {
            // NOTE: Round the `bondCurveDelta` down to underestimate the share
            // proceeds.
            //
            // Calculate the curved part of the trade.
            bondCurveDelta = _amountIn.mulDown(_normalizedTimeRemaining);

            // NOTE: Round the `shareCurveDelta` down to underestimate the
            // share proceeds.
            shareCurveDelta = YieldSpaceMath.calculateSharesOutGivenBondsInDown(
                _effectiveShareReserves,
                _bondReserves,
                bondCurveDelta,
                // NOTE: Since the bonds traded on the curve are newly minted,
                // we use a time remaining of 1. This means that we can use
                // `_timeStretch = t * _timeStretch`.
                ONE - _timeStretch,
                _vaultSharePrice,
                _initialVaultSharePrice
            );
            shareProceeds += shareCurveDelta;
        }
    }

    /// @dev Calculates the amount of shares that will be received given a
    ///      specified amount of bonds.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _bondReserves The pool's bonds reserves.
    /// @param _amountIn The amount of bonds the user is providing.
    /// @param _timeStretch The time stretch parameter.
    /// @param _vaultSharePrice The vault share price.
    /// @param _initialVaultSharePrice The initial vault share price.
    /// @return The shares paid by the reserves in the trade.
    function calculateOpenShort(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _timeStretch,
        uint256 _vaultSharePrice,
        uint256 _initialVaultSharePrice
    ) internal pure returns (uint256) {
        // NOTE: We underestimate the LP's share payment to avoid sandwiches.
        return
            YieldSpaceMath.calculateSharesOutGivenBondsInDown(
                _effectiveShareReserves,
                _bondReserves,
                _amountIn,
                // NOTE: Since the bonds traded on the curve are newly minted,
                // we use a time remaining of 1. This means that we can use
                // `_timeStretch = t * _timeStretch`.
                ONE - _timeStretch,
                _vaultSharePrice,
                _initialVaultSharePrice
            );
    }

    /// @dev Calculates the amount of base that a user will receive when closing
    ///      a short position.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _bondReserves The pool's bonds reserves.
    /// @param _amountOut The amount of the asset that is received.
    /// @param _normalizedTimeRemaining The amount of time remaining until
    ///        maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @param _vaultSharePrice The vault share price.
    /// @param _initialVaultSharePrice The initial vault share price.
    /// @return shareCurveDelta The shares paid to the reserves in the trade.
    /// @return bondCurveDelta The bonds paid by the reserves in the trade.
    /// @return sharePayment The shares that the user must pay.
    function calculateCloseShort(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _vaultSharePrice,
        uint256 _initialVaultSharePrice
    )
        internal
        pure
        returns (
            uint256 shareCurveDelta,
            uint256 bondCurveDelta,
            uint256 sharePayment
        )
    {
        // NOTE: We overestimate the trader's share payment to avoid sandwiches.
        //
        // Since we are buying bonds, it's possible that `timeRemaining < 1`.
        // We consider `(1 - timeRemaining) * amountOut` of the bonds being
        // purchased to be fully matured and `timeRemaining * amountOut of the
        // bonds to be newly minted. The fully matured bonds are redeemed
        // one-to-one to base (our result is given in shares, so we divide
        // the one-to-one redemption by the vault share price) and the newly
        // minted bonds are traded on a YieldSpace curve configured to
        // timeRemaining = 1.
        sharePayment = _amountOut.mulDivUp(
            ONE - _normalizedTimeRemaining,
            _vaultSharePrice
        );
        if (_normalizedTimeRemaining > 0) {
            // NOTE: Round the `bondCurveDelta` up to overestimate the share
            // payment.
            bondCurveDelta = _amountOut.mulUp(_normalizedTimeRemaining);

            // NOTE: Round the `shareCurveDelta` up to overestimate the share
            // payment.
            shareCurveDelta = YieldSpaceMath.calculateSharesInGivenBondsOutUp(
                _effectiveShareReserves,
                _bondReserves,
                bondCurveDelta,
                // NOTE: Since the bonds traded on the curve are newly minted,
                // we use a time remaining of 1. This means that we can use
                // `_timeStretch = t * _timeStretch`.
                ONE - _timeStretch,
                _vaultSharePrice,
                _initialVaultSharePrice
            );
            sharePayment += shareCurveDelta;
        }
    }

    /// @dev If negative interest accrued over the term, we scale the share
    ///      proceeds by the negative interest amount. Shorts should be
    ///      responsible for negative interest, but negative interest can exceed
    ///      the margin that shorts provide. This leaves us with no choice but
    ///      to attribute the negative interest to longs. Along with scaling the
    ///      share proceeds, we also scale the fee amounts.
    ///
    ///      In order for our AMM invariant to be maintained, the effective
    ///      share reserves need to be adjusted by the same amount as the share
    ///      reserves delta calculated with YieldSpace including fees. We reduce
    ///      the share reserves by `min(c_1 / c_0, 1) * shareReservesDelta` and
    ///      the share adjustment by the `shareAdjustmentDelta`. We can solve
    ///      these equations simultaneously to find the share adjustment delta
    ///      as:
    ///
    ///      shareAdjustmentDelta = min(c_1 / c_0, 1) * sharePayment -
    ///                             shareReservesDelta
    ///
    ///      We underestimate the share proceeds to avoid sandwiches, and we
    ///      round the share reserves delta and share adjustment in the same
    ///      direction for consistency.
    /// @param _shareProceeds The proceeds in shares from the trade.
    /// @param _shareReservesDelta The change in share reserves from the trade.
    /// @param _shareCurveDelta The curve portion of the change in share reserves.
    /// @param _totalGovernanceFee The total governance fee.
    /// @param _openVaultSharePrice The vault share price at the beginning of
    ///        the term.
    /// @param _closeVaultSharePrice The vault share price at the end of the term.
    /// @param _isLong A flag indicating whether or not the trade is a long.
    /// @return The adjusted share proceeds.
    /// @return The adjusted share reserves delta.
    /// @return The adjusted share close proceeds.
    /// @return The share adjustment delta.
    /// @return The adjusted total governance fee.
    function calculateNegativeInterestOnClose(
        uint256 _shareProceeds,
        uint256 _shareReservesDelta,
        uint256 _shareCurveDelta,
        uint256 _totalGovernanceFee,
        uint256 _openVaultSharePrice,
        uint256 _closeVaultSharePrice,
        bool _isLong
    ) internal pure returns (uint256, uint256, uint256, int256, uint256) {
        // The share reserves delta, share curve delta, and total governance fee
        // need to be scaled down in proportion to the negative interest. This
        // results in the pool receiving a lower payment, which reflects the
        // fact that negative interest is attributed to longs.
        //
        // In order for our AMM invariant to be maintained, the effective share
        // reserves need to be adjusted by the same amount as the share reserves
        // delta calculated with YieldSpace including fees. We increase the
        // share reserves by `min(c_1 / c_0, 1) * shareReservesDelta` and the
        // share adjustment by the `shareAdjustmentDelta`. We can solve these
        // equations simultaneously to find the share adjustment delta as:
        //
        // shareAdjustmentDelta = min(c_1 / c_0, 1) * shareReservesDelta -
        //                        shareCurveDelta
        int256 shareAdjustmentDelta;
        if (_closeVaultSharePrice < _openVaultSharePrice) {
            // NOTE: Round down to underestimate the share proceeds.
            //
            // We only need to scale the proceeds in the case that we're closing
            // a long since `calculateShortProceeds` accounts for negative
            // interest.
            if (_isLong) {
                _shareProceeds = _shareProceeds.mulDivDown(
                    _closeVaultSharePrice,
                    _openVaultSharePrice
                );
            }

            // NOTE: Round down to underestimate the quantities.
            //
            // Scale the other values.
            _shareReservesDelta = _shareReservesDelta.mulDivDown(
                _closeVaultSharePrice,
                _openVaultSharePrice
            );
            // NOTE: Using unscaled `shareCurveDelta`.
            shareAdjustmentDelta =
                _shareReservesDelta.toInt256() -
                _shareCurveDelta.toInt256();
            _shareCurveDelta = _shareCurveDelta.mulDivDown(
                _closeVaultSharePrice,
                _openVaultSharePrice
            );
            _totalGovernanceFee = _totalGovernanceFee.mulDivDown(
                _closeVaultSharePrice,
                _openVaultSharePrice
            );
        } else {
            shareAdjustmentDelta =
                _shareReservesDelta.toInt256() -
                _shareCurveDelta.toInt256();
        }

        return (
            _shareProceeds,
            _shareReservesDelta,
            _shareCurveDelta,
            shareAdjustmentDelta,
            _totalGovernanceFee
        );
    }
}
