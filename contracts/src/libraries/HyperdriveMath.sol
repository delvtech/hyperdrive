/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { FixedPointMath, ONE } from "./FixedPointMath.sol";
import { YieldSpaceMath } from "./YieldSpaceMath.sol";
import { SafeCast } from "./SafeCast.sol";

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

    /// @dev Calculates the spot price of bonds in terms of base.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _initialSharePrice The initial share price.
    /// @param _timeStretch The time stretch parameter.
    /// @return spotPrice The spot price of bonds in terms of base.
    function calculateSpotPrice(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _initialSharePrice,
        uint256 _timeStretch
    ) internal pure returns (uint256 spotPrice) {
        // p = (y / (mu * (z - zeta))) ** -t_s
        //   = ((mu * (z - zeta)) / y) ** t_s
        spotPrice = _initialSharePrice
            .mulDivDown(_effectiveShareReserves, _bondReserves)
            .pow(_timeStretch);
    }

    /// @dev Calculates the spot APR of the pool.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _initialSharePrice The pool's initial share price.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @return apr The pool's spot APR.
    function calculateSpotAPR(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _initialSharePrice,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 apr) {
        // We are interested calculating the fixed APR for the pool. The annualized rate
        // is given by the following formula:
        // r = (1 - p) / (p * t)
        // where t = _positionDuration / 365
        uint256 spotPrice = calculateSpotPrice(
            _effectiveShareReserves,
            _bondReserves,
            _initialSharePrice,
            _timeStretch
        );
        return
            (ONE - spotPrice).divDown(
                spotPrice.mulDivUp(_positionDuration, 365 days)
            );
    }

    /// @dev Calculates the initial bond reserves assuming that the initial LP
    ///      receives LP shares amounting to c * z + y. Throughout the rest of
    ///      the codebase, the bond reserves used include the LP share
    ///      adjustment specified in YieldSpace. The bond reserves returned by
    ///      this function are unadjusted which makes it easier to calculate the
    ///      initial LP shares.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _initialSharePrice The pool's initial share price.
    /// @param _apr The pool's APR.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @return bondReserves The bond reserves (without adjustment) that make
    ///         the pool have a specified APR.
    function calculateInitialBondReserves(
        uint256 _effectiveShareReserves,
        uint256 _initialSharePrice,
        uint256 _apr,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 bondReserves) {
        // NOTE: Using divDown to convert to fixed point format.
        uint256 t = _positionDuration.divDown(365 days);

        // mu * (z - zeta) * (1 + apr * t) ** (1 / tau)
        return
            _initialSharePrice.mulDown(_effectiveShareReserves).mulDown(
                (ONE + _apr.mulDown(t)).pow(ONE.divUp(_timeStretch))
            );
    }

    /// @dev Since traders pay a curve fee when they open longs on Hyperdrive,
    ///      it is possible for traders to receive a negative interest rate even
    ///      if curve's spot price is less than or equal to 1.
    ///
    ///      Given the curve fee `phi_c` and the starting spot price `p_0`, the
    ///      maximum spot price is given by:
    ///
    ///      p_max = (1 - phi_f) / (1 + phi_c * (1 / p_0 - 1)(1 - phi_f))
    ///
    /// @param _startingSpotPrice The spot price at the start of the trade.
    /// @param _curveFee The curve fee.
    /// @param _flatFee The flat fee.
    /// @return The maximum spot price.
    function calculateOpenLongMaxSpotPrice(
        uint256 _startingSpotPrice,
        uint256 _curveFee,
        uint256 _flatFee
    ) internal pure returns (uint256) {
        return
            (ONE - _flatFee).divDown(
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
    /// @param _startingSpotPrice The spot price at the start of the trade.
    /// @param _curveFee The curve fee.
    /// @return The maximum spot price.
    function calculateCloseShortMaxSpotPrice(
        uint256 _startingSpotPrice,
        uint256 _curveFee
    ) internal pure returns (uint256) {
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
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return bondReservesDelta The bonds paid by the reserves in the trade.
    function calculateOpenLong(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _shareAmount,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
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
                _sharePrice,
                _initialSharePrice
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
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The share price when the pool was deployed.
    /// @return shareCurveDelta The shares paid by the reserves in the trade.
    /// @return bondCurveDelta The bonds paid to the reserves in the trade.
    /// @return shareProceeds The shares that the user will receive.
    function calculateCloseLong(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    )
        internal
        pure
        returns (
            uint256 shareCurveDelta,
            uint256 bondCurveDelta,
            uint256 shareProceeds
        )
    {
        // We consider `(1 - timeRemaining) * amountIn` of the bonds to be fully
        // matured and timeRemaining * amountIn of the bonds to be newly
        // minted. The fully matured bonds are redeemed one-to-one to base
        // (our result is given in shares, so we divide the one-to-one
        // redemption by the share price) and the newly minted bonds are
        // traded on a YieldSpace curve configured to `timeRemaining = 1`.
        shareProceeds = _amountIn.mulDivDown(
            ONE - _normalizedTimeRemaining,
            _sharePrice
        );
        if (_normalizedTimeRemaining > 0) {
            // Calculate the curved part of the trade.
            bondCurveDelta = _amountIn.mulDown(_normalizedTimeRemaining);

            // NOTE: We underestimate the trader's share proceeds to avoid
            // sandwich attacks.
            shareCurveDelta = YieldSpaceMath.calculateSharesOutGivenBondsInDown(
                _effectiveShareReserves,
                _bondReserves,
                bondCurveDelta,
                // NOTE: Since the bonds traded on the curve are newly minted,
                // we use a time remaining of 1. This means that we can use
                // `_timeStretch = t * _timeStretch`.
                ONE - _timeStretch,
                _sharePrice,
                _initialSharePrice
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
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return The shares paid by the reserves in the trade.
    function calculateOpenShort(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
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
                _sharePrice,
                _initialSharePrice
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
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return shareCurveDelta The shares paid to the reserves in the trade.
    /// @return bondCurveDelta The bonds paid by the reserves in the trade.
    /// @return sharePayment The shares that the user must pay.
    function calculateCloseShort(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    )
        internal
        pure
        returns (
            uint256 shareCurveDelta,
            uint256 bondCurveDelta,
            uint256 sharePayment
        )
    {
        // Since we are buying bonds, it's possible that `timeRemaining < 1`.
        // We consider `(1 - timeRemaining) * amountOut` of the bonds being
        // purchased to be fully matured and `timeRemaining * amountOut of the
        // bonds to be newly minted. The fully matured bonds are redeemed
        // one-to-one to base (our result is given in shares, so we divide
        // the one-to-one redemption by the share price) and the newly
        // minted bonds are traded on a YieldSpace curve configured to
        // timeRemaining = 1.
        sharePayment = _amountOut.mulDivDown(
            ONE - _normalizedTimeRemaining,
            _sharePrice
        );
        if (_normalizedTimeRemaining > 0) {
            bondCurveDelta = _amountOut.mulDown(_normalizedTimeRemaining);

            // NOTE: We overestimate the trader's share payment to avoid
            // sandwiches.
            shareCurveDelta = YieldSpaceMath.calculateSharesInGivenBondsOutUp(
                _effectiveShareReserves,
                _bondReserves,
                bondCurveDelta,
                // NOTE: Since the bonds traded on the curve are newly minted,
                // we use a time remaining of 1. This means that we can use
                // `_timeStretch = t * _timeStretch`.
                ONE - _timeStretch,
                _sharePrice,
                _initialSharePrice
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
    /// @param _shareProceeds The proceeds in shares from the trade.
    /// @param _shareReservesDelta The change in share reserves from the trade.
    /// @param _shareCurveDelta The curve portion of the change in share reserves.
    /// @param _totalGovernanceFee The total governance fee.
    /// @param _openSharePrice The share price at the beginning of the term.
    /// @param _closeSharePrice The share price at the end of the term.
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
        uint256 _openSharePrice,
        uint256 _closeSharePrice,
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
        if (_closeSharePrice < _openSharePrice) {
            // We only need to scale the proceeds in the case that we're closing
            // a long since `calculateShortProceeds` accounts for negative
            // interest.
            if (_isLong) {
                _shareProceeds = _shareProceeds.mulDivDown(
                    _closeSharePrice,
                    _openSharePrice
                );
            }

            // Scale the other values.
            _shareReservesDelta = _shareReservesDelta.mulDivDown(
                _closeSharePrice,
                _openSharePrice
            );
            // NOTE: Using unscaled `shareCurveDelta`.
            shareAdjustmentDelta =
                int256(_shareReservesDelta) -
                int256(_shareCurveDelta);
            _shareCurveDelta = _shareCurveDelta.mulDivDown(
                _closeSharePrice,
                _openSharePrice
            );
            _totalGovernanceFee = _totalGovernanceFee.mulDivDown(
                _closeSharePrice,
                _openSharePrice
            );
        } else {
            shareAdjustmentDelta =
                int256(_shareReservesDelta) -
                int256(_shareCurveDelta);
        }

        return (
            _shareProceeds,
            _shareReservesDelta,
            _shareCurveDelta,
            shareAdjustmentDelta,
            _totalGovernanceFee
        );
    }

    struct PresentValueParams {
        uint256 shareReserves;
        int256 shareAdjustment;
        uint256 bondReserves;
        uint256 sharePrice;
        uint256 initialSharePrice;
        uint256 minimumShareReserves;
        uint256 timeStretch;
        uint256 longsOutstanding;
        uint256 longAverageTimeRemaining;
        uint256 shortsOutstanding;
        uint256 shortAverageTimeRemaining;
    }

    /// @dev Calculates the present value LPs capital in the pool.
    /// @param _params The parameters for the present value calculation.
    /// @return The present value of the pool.
    function calculatePresentValue(
        PresentValueParams memory _params
    ) internal pure returns (uint256) {
        // We calculate the LP present value by simulating the closing of all
        // of the outstanding long and short positions and applying this impact
        // on the share reserves. The present value is the share reserves after
        // the impact of the trades minus the minimum share reserves:
        //
        // PV = z + net_c + net_f - z_min
        int256 presentValue = int256(_params.shareReserves) +
            calculateNetCurveTrade(_params) +
            calculateNetFlatTrade(_params) -
            int256(_params.minimumShareReserves);

        // If the present value is negative, we revert.
        if (presentValue < 0) {
            revert IHyperdrive.NegativePresentValue();
        }

        return uint256(presentValue);
    }

    /// @dev Calculates the result of closing the net curve position.
    /// @param _params The parameters for the present value calculation.
    /// @return The impact of closing the net curve position on the share
    ///         reserves.
    function calculateNetCurveTrade(
        PresentValueParams memory _params
    ) internal pure returns (int256) {
        // The net curve position is the net of the longs and shorts that are
        // currently tradeable on the curve. Given the amount of outstanding
        // longs `y_l` and shorts `y_s` as well as the average time remaining
        // of outstanding longs `t_l` and shorts `t_s`, we can
        // compute the net curve position as:
        //
        // netCurveTrade = y_l * t_l - y_s * t_s.
        int256 netCurvePosition = int256(
            _params.longsOutstanding.mulDown(_params.longAverageTimeRemaining)
        ) -
            int256(
                _params.shortsOutstanding.mulDown(
                    _params.shortAverageTimeRemaining
                )
            );
        uint256 effectiveShareReserves = calculateEffectiveShareReserves(
            _params.shareReserves,
            _params.shareAdjustment
        );

        // If the net curve position is positive, then the pool is net long.
        // Closing the net curve position results in the longs being paid out
        // from the share reserves, so we negate the result.
        if (netCurvePosition > 0) {
            uint256 netCurvePosition_ = uint256(netCurvePosition);

            // Calculate the maximum amount of bonds that can be sold on
            // YieldSpace.
            uint256 maxCurveTrade = YieldSpaceMath.calculateMaxSellBondsIn(
                effectiveShareReserves,
                _params.bondReserves,
                _params.minimumShareReserves,
                ONE - _params.timeStretch,
                _params.sharePrice,
                _params.initialSharePrice
            );

            // If the max curve trade is greater than the net curve position,
            // then we can close the entire net curve position.
            if (maxCurveTrade >= netCurvePosition_) {
                uint256 netCurveTrade = YieldSpaceMath
                    .calculateSharesOutGivenBondsInDown(
                        effectiveShareReserves,
                        _params.bondReserves,
                        netCurvePosition_,
                        ONE - _params.timeStretch,
                        _params.sharePrice,
                        _params.initialSharePrice
                    );
                return -int256(netCurveTrade);
            }
            // Otherwise, we can only close part of the net curve position.
            // Since the spot price is approximately zero after closing the
            // entire net curve position, we mark any remaining bonds to zero.
            else {
                return
                    -int256(
                        effectiveShareReserves - _params.minimumShareReserves
                    );
            }
        }
        // If the net curve position is negative, then the pool is net short.
        else if (netCurvePosition < 0) {
            uint256 netCurvePosition_ = uint256(-netCurvePosition);

            // Calculate the maximum amount of bonds that can be bought on
            // YieldSpace.
            uint256 maxCurveTrade = YieldSpaceMath.calculateMaxBuyBondsOut(
                effectiveShareReserves,
                _params.bondReserves,
                ONE - _params.timeStretch,
                _params.sharePrice,
                _params.initialSharePrice
            );

            // If the max curve trade is greater than the net curve position,
            // then we can close the entire net curve position.
            if (maxCurveTrade >= netCurvePosition_) {
                uint256 netCurveTrade = YieldSpaceMath
                    .calculateSharesInGivenBondsOutUp(
                        effectiveShareReserves,
                        _params.bondReserves,
                        netCurvePosition_,
                        ONE - _params.timeStretch,
                        _params.sharePrice,
                        _params.initialSharePrice
                    );
                return int256(netCurveTrade);
            }
            // Otherwise, we can only close part of the net curve position.
            // Since the spot price is equal to one after closing the entire net
            // curve position, we mark any remaining bonds to one.
            else {
                uint256 maxSharePayment = YieldSpaceMath
                    .calculateMaxBuySharesIn(
                        effectiveShareReserves,
                        _params.bondReserves,
                        ONE - _params.timeStretch,
                        _params.sharePrice,
                        _params.initialSharePrice
                    );
                return
                    int256(
                        maxSharePayment +
                            (netCurvePosition_ - maxCurveTrade).divDown(
                                _params.sharePrice
                            )
                    );
            }
        }

        return 0;
    }

    /// @dev Calculates the result of closing the net flat position.
    /// @param _params The parameters for the present value calculation.
    /// @return The impact of closing the net flat position on the share
    ///         reserves.
    function calculateNetFlatTrade(
        PresentValueParams memory _params
    ) internal pure returns (int256) {
        // The net curve position is the net of the component of longs and
        // shorts that have matured. Given the amount of outstanding longs `y_l`
        // and shorts `y_s` as well as the average time remaining of outstanding
        // longs `t_l` and shorts `t_s`, we can compute the net flat trade as:
        //
        // netFlatTrade = y_s * (1 - t_s) - y_l * (1 - t_l).
        return
            int256(
                _params.shortsOutstanding.mulDivDown(
                    ONE - _params.shortAverageTimeRemaining,
                    _params.sharePrice
                )
            ) -
            int256(
                _params.longsOutstanding.mulDivDown(
                    ONE - _params.longAverageTimeRemaining,
                    _params.sharePrice
                )
            );
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
    ///      We convert the proceeds to shares by dividing by the current share
    ///      price. In the event that the interest is negative and outweighs the
    ///      trading profits and margin released, the short's proceeds are
    ///      marked to zero.
    /// @param _bondAmount The amount of bonds underlying the closed short.
    /// @param _shareAmount The amount of shares that it costs to close the
    ///                     short.
    /// @param _openSharePrice The share price at the short's open.
    /// @param _closeSharePrice The share price at the short's close.
    /// @param _sharePrice The current share price.
    /// @param _flatFee The flat fee currently within the pool
    /// @return shareProceeds The short proceeds in shares.
    function calculateShortProceeds(
        uint256 _bondAmount,
        uint256 _shareAmount,
        uint256 _openSharePrice,
        uint256 _closeSharePrice,
        uint256 _sharePrice,
        uint256 _flatFee
    ) internal pure returns (uint256 shareProceeds) {
        // If the interest is more negative than the trading profits and margin
        // released, than the short proceeds are marked to zero. Otherwise, we
        // calculate the proceeds as the sum of the trading proceeds, the
        // interest proceeds, and the margin released.
        uint256 bondFactor = _bondAmount.mulDivDown(
            _closeSharePrice,
            // We round up here do avoid overestimating the share proceeds.
            _openSharePrice.mulUp(_sharePrice)
        );

        // We increase the bondFactor by the flat fee amount, because the trader
        // has provided the flat fee as margin, and so it must be returned to
        // them if it's not charged.
        bondFactor += _bondAmount.mulDivDown(_flatFee, _sharePrice);

        if (bondFactor > _shareAmount) {
            // proceeds = (c1 / c0 * c) * dy - dz
            shareProceeds = bondFactor - _shareAmount;
        }
        return shareProceeds;
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
    function calculateEffectiveShareReserves(
        uint256 _shareReserves,
        int256 _shareAdjustment
    ) internal pure returns (uint256) {
        int256 effectiveShareReserves = int256(_shareReserves) -
            _shareAdjustment;
        require(effectiveShareReserves >= 0);
        return uint256(effectiveShareReserves);
    }
}
