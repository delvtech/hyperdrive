/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Errors } from "./Errors.sol";
import { FixedPointMath } from "./FixedPointMath.sol";
import { YieldSpaceMath } from "./YieldSpaceMath.sol";
import "forge-std/console2.sol";

/// @author DELV
/// @title Hyperdrive
/// @notice Math for the Hyperdrive pricing model.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library HyperdriveMath {
    using FixedPointMath for uint256;

    /// @dev Calculates the spot price without slippage of bonds in terms of shares.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _initialSharePrice The initial share price as an 18 fixed-point value.
    /// @param _normalizedTimeRemaining The normalized amount of time remaining until maturity.
    /// @param _timeStretch The time stretch parameter as an 18 fixed-point value.
    /// @return spotPrice The spot price of bonds in terms of shares as an 18 fixed-point value.
    function calculateSpotPrice(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _initialSharePrice,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch
    ) internal pure returns (uint256 spotPrice) {
        // (y / (mu * z)) ** -tau
        // ((mu * z) / y) ** tau
        uint256 tau = _normalizedTimeRemaining.mulDown(_timeStretch);

        spotPrice = _initialSharePrice
            .mulDivDown(_shareReserves, _bondReserves)
            .pow(tau);
    }

    /// @dev Calculates the APR from the pool's reserves.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _initialSharePrice The pool's initial share price.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @return apr The pool's APR.
    function calculateAPRFromReserves(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _initialSharePrice,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 apr) {
        // We are interested calculating the fixed APR for the pool. The rate is calculated by
        // dividing current spot price of the bonds by the position duration time, t.  To get the
        // annual rate, we scale t up to a year.
        uint256 annualizedTime = _positionDuration.divDown(365 days);

        uint256 spotPrice = calculateSpotPrice(
            _shareReserves,
            _bondReserves,
            _initialSharePrice,
            // full time remaining of position
            FixedPointMath.ONE_18,
            _timeStretch
        );

        // r = (1 - p) / (p * t)
        return
            FixedPointMath.ONE_18.sub(spotPrice).divDown(
                spotPrice.mulDown(annualizedTime)
            );
    }

    /// @dev Calculates the initial bond reserves assuming that the initial LP
    ///      receives LP shares amounting to c * z + y. Throughout the rest of
    ///      the codebase, the bond reserves used include the LP share
    ///      adjustment specified in YieldSpace. The bond reserves returned by
    ///      this function are unadjusted which makes it easier to calculate the
    ///      initial LP shares.
    /// @param _shareReserves The pool's share reserves.
    /// @param _sharePrice The pool's share price.
    /// @param _initialSharePrice The pool's initial share price.
    /// @param _apr The pool's APR.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @return bondReserves The bond reserves (without adjustment) that make
    ///         the pool have a specified APR.
    function calculateInitialBondReserves(
        uint256 _shareReserves,
        uint256 _sharePrice,
        uint256 _initialSharePrice,
        uint256 _apr,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 bondReserves) {
        // NOTE: Using divDown to convert to fixed point format.
        uint256 t = _positionDuration.divDown(365 days);
        uint256 tau = FixedPointMath.ONE_18.mulDown(_timeStretch);
        // mu * (1 + apr * t) ** (1 / tau) - c
        uint256 rhs = _initialSharePrice
            .mulDown(
                FixedPointMath.ONE_18.add(_apr.mulDown(t)).pow(
                    FixedPointMath.ONE_18.divUp(tau)
                )
            )
            .sub(_sharePrice);
        // (z / 2) * (mu * (1 + apr * t) ** (1 / tau) - c)
        return _shareReserves.divDown(2 * FixedPointMath.ONE_18).mulDown(rhs);
    }

    /// @dev Calculates the number of bonds a user will receive when opening a long position.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _shareAmount The amount of shares the user is depositing.
    /// @param _normalizedTimeRemaining The amount of time remaining until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return shareReservesDelta The shares paid to the reserves in the trade.
    /// @return bondReservesDelta The bonds paid by the reserves in the trade.
    /// @return bondProceeds The bonds that the user will receive.
    function calculateOpenLong(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _shareAmount,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    )
        internal
        view
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 bondProceeds
        )
    {
        console2.log("open long:");
        console2.log("amount in", _shareAmount);
        console2.log("time remaining", _normalizedTimeRemaining);
        console2.log("share price", _sharePrice);
        // Calculate the flat part of the trade.
        bondProceeds = _shareAmount
            .mulDown(FixedPointMath.ONE_18.sub(_normalizedTimeRemaining))
            .mulDown(_sharePrice);
        console2.log("bonds coming out of flat:", bondProceeds);
        shareReservesDelta = _shareAmount.mulDown(_normalizedTimeRemaining);
        console2.log("shares trading into the curve", shareReservesDelta);
    
        // (time remaining)/(term length) is always 1 so we just use _timeStretch
        bondReservesDelta = YieldSpaceMath.calculateBondsOutGivenSharesIn(
            _shareReserves,
            _bondReserves,
            shareReservesDelta,
            FixedPointMath.ONE_18.sub(_timeStretch),
            _sharePrice,
            _initialSharePrice
        );
        console2.log("bond delta / share delta: ", bondReservesDelta.divDown(shareReservesDelta));
        console2.log("trade share reserves:", _shareReserves);
        console2.log("trade bond reserves:", _bondReserves);
        console2.log("bonds/base: ", _bondReserves.divDown(_shareReserves));
        console2.log("bonds coming out of the curve", bondReservesDelta);
        bondProceeds += bondReservesDelta;
        console2.log("total bonds coming out", bondProceeds);
        // you can get the flat amount by subtracting shareReservesDelta from _shareAmount
        return (shareReservesDelta, bondReservesDelta, bondProceeds);
    }

    /// @dev Calculates the amount of shares a user will receive when closing a
    ///      long position.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _amountIn The amount of bonds the user is closing.
    /// @param _normalizedTimeRemaining The normalized time remaining of the
    ///        position.
    /// @param _timeStretch The time stretch parameter.
    /// @param _closeSharePrice The share price at close.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return shareReservesDelta The shares paid by the reserves in the trade.
    /// @return bondReservesDelta The bonds paid to the reserves in the trade.
    /// @return shareProceeds The shares that the user will receive.
    function calculateCloseLong(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _closeSharePrice,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    )
        internal
        view
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 shareProceeds
        )
    {
        // We consider (1 - timeRemaining) * amountIn of the bonds to be fully
        // matured and timeRemaining * amountIn of the bonds to be newly
        // minted. The fully matured bonds are redeemed one-to-one to base
        // (our result is given in shares, so we divide the one-to-one
        // redemption by the share price) and the newly minted bonds are
        // traded on a YieldSpace curve configured to timeRemaining = 1.
        console2.log("close long:");
        console2.log("amount in", _amountIn);
        console2.log("time remaining", _normalizedTimeRemaining);
        console2.log("share price", _sharePrice);
        shareProceeds = _amountIn.mulDivDown(
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining),
            _sharePrice
        );
        console2.log("shares coming out of flat:", shareProceeds);
        if (_normalizedTimeRemaining > 0) {
            // Calculate the curved part of the trade.
            bondReservesDelta = _amountIn.mulDown(_normalizedTimeRemaining);
            console2.log("bonds trading into the curve", bondReservesDelta);
            //_shareReserves/_bondReserves = (_shareReserves - shareProceeds)/(_bondReserves-dy)
            //bondReserves - dy = (_shareReserves - shareProceeds)*(_bondReserves/_shareReserves)
            //uint256 dy = _bondReserves - (_shareReserves - shareProceeds).mulDown(_bondReserves.divDown(_shareReserves));
            // (time remaining)/(term length) is always 1 so we just use _timeStretch
            shareReservesDelta = YieldSpaceMath.calculateSharesOutGivenBondsIn(
                _shareReserves,//-shareProceeds,
                _bondReserves,//-dy,
                bondReservesDelta,
                FixedPointMath.ONE_18.sub(_timeStretch),
                _sharePrice,
                _initialSharePrice
            );
            console2.log("trade share reserves:", _shareReserves-shareProceeds);
            console2.log("trade bond reserves:", _bondReserves);
            console2.log("bonds/base: ", _bondReserves.divDown(_shareReserves-shareProceeds));
            console2.log("shares coming out of the curve", shareReservesDelta);
            shareProceeds += shareReservesDelta;
            console2.log("total shares coming out", shareProceeds);
        }

        // If there's net negative interest over the period, the result of close long
        // is adjusted down by the rate of negative interest. We always attribute negative
        // interest to the long since it's difficult or impossible to attribute
        // the negative interest to the short in practice.
        if (_initialSharePrice > _closeSharePrice) {
            shareProceeds = shareProceeds.mulDivDown(
                _closeSharePrice,
                _initialSharePrice
            );
        }

        return (shareReservesDelta, bondReservesDelta, shareProceeds);
    }

    /// @dev Calculates the amount of shares that will be received given a
    ///      specified amount of bonds.
    /// @param _shareReserves The pool's share reserves
    /// @param _bondReserves The pool's bonds reserves.
    /// @param _amountIn The amount of bonds the user is providing.
    /// @param _normalizedTimeRemaining The amount of time remaining until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return shareReservesDelta The shares paid by the reserves in the trade.
    /// @return bondReservesDelta The bonds paid to the reserves in the trade.
    /// @return shareProceeds The shares that the user will receive.
    function calculateOpenShort(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    )
        internal
        view
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 shareProceeds
        )
    {
        console2.log("open short:");
        console2.log("amount in", _amountIn);
        console2.log("time remaining", _normalizedTimeRemaining);
        console2.log("share price", _sharePrice);
        // Calculate the flat part of the trade.
        shareProceeds = _amountIn
            .mulDown(FixedPointMath.ONE_18.sub(_normalizedTimeRemaining))
            .divDown(_sharePrice);
        console2.log("shares coming out of flat:", shareProceeds);
        // Calculate the curved part of the trade.
        bondReservesDelta = _amountIn.mulDown(_normalizedTimeRemaining);
        console2.log("bonds trading into the curve", bondReservesDelta);
        // (time remaining)/(term length) is always 1 so we just use _timeStretch
        shareReservesDelta = YieldSpaceMath.calculateSharesOutGivenBondsIn(
            _shareReserves,
            _bondReserves,
            bondReservesDelta,
            FixedPointMath.ONE_18.sub(_timeStretch),
            _sharePrice,
            _initialSharePrice
        );
        console2.log("shares coming out of the curve", shareReservesDelta);
        console2.log("bond delta / share delta: ", bondReservesDelta.divDown(shareReservesDelta));
        console2.log("trade share reserves:", _shareReserves);
        console2.log("trade bond reserves:", _bondReserves);
        console2.log("bonds/base: ", _bondReserves.divDown(_shareReserves));
        shareProceeds += shareReservesDelta;
        console2.log("total shares coming out", shareProceeds);
        return (shareReservesDelta, bondReservesDelta, shareProceeds);
    }

    /// @dev Calculates the amount of base that a user will receive when closing a short position
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bonds reserves.
    /// @param _amountOut The amount of the asset that is received.
    /// @param _normalizedTimeRemaining The amount of time remaining until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return shareReservesDelta The shares paid to the reserves in the trade.
    /// @return bondReservesDelta The bonds paid by the reserves in the trade.
    /// @return sharePayment The shares that the user must pay.
    function calculateCloseShort(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    )
        internal
        view
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 sharePayment
        )
    {
        console2.log("close short:");
        console2.log("amount out", _amountOut);
        console2.log("time remaining", _normalizedTimeRemaining);
        console2.log("share price", _sharePrice);
        // Since we are buying bonds, it's possible that timeRemaining < 1.
        // We consider (1-timeRemaining)*amountOut of the bonds being
        // purchased to be fully matured and timeRemaining*amountOut of the
        // bonds to be newly minted. The fully matured bonds are redeemed
        // one-to-one to base (our result is given in shares, so we divide
        // the one-to-one redemption by the share price) and the newly
        // minted bonds are traded on a YieldSpace curve configured to
        // timeRemaining = 1.
        sharePayment = _amountOut.mulDivDown(
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining),
            _sharePrice
        );
        console2.log("shares coming out of flat:", sharePayment);
        if (_normalizedTimeRemaining > 0) {
            bondReservesDelta = _amountOut.mulDown(_normalizedTimeRemaining);
            console2.log("bonds trading into the curve", bondReservesDelta);
            shareReservesDelta = YieldSpaceMath.calculateSharesInGivenBondsOut(
                _shareReserves,
                _bondReserves,
                bondReservesDelta,
                FixedPointMath.ONE_18.sub(_timeStretch),
                _sharePrice,
                _initialSharePrice
            );
            console2.log("shares coming out of the curve", shareReservesDelta);
            console2.log("bond delta / share delta: ", bondReservesDelta.divDown(shareReservesDelta));
            console2.log("trade share reserves:", _shareReserves);
            console2.log("trade bond reserves:", _bondReserves);
            console2.log("bonds/base: ", _bondReserves.divDown(_shareReserves));
            sharePayment += shareReservesDelta;
            console2.log("total shares coming out", sharePayment);
        }

        return (shareReservesDelta, bondReservesDelta, sharePayment);
    }

    struct PresentValueParams {
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 sharePrice;
        uint256 initialSharePrice;
        uint256 timeStretch;
        uint256 longsOutstanding;
        uint256 longAverageTimeRemaining;
        uint256 shortsOutstanding;
        uint256 shortAverageTimeRemaining;
        uint256 shortBaseVolume;
    }

    /// @dev Calculates the present value LPs capital in the pool.
    /// @param _params The parameters for the present value calculation.
    /// @return The present value of the pool.
    function calculatePresentValue(
        PresentValueParams memory _params
    ) internal pure returns (uint256) {
        // Compute the net of the longs and shorts that will be traded on the
        // curve and apply this net to the reserves.
        int256 netCurveTrade = int256(
            _params.longsOutstanding.mulDown(_params.longAverageTimeRemaining)
        ) -
            int256(
                _params.shortsOutstanding.mulDown(
                    _params.shortAverageTimeRemaining
                )
            );
        if (netCurveTrade > 0) {
            // Apply the curve trade directly to the reserves. Unlike shorts,
            // the capital that backs longs is accounted for within the share
            // reserves (the capital backing shorts is taken out of the
            // reserves). This ensures that even if all the liquidity is
            // removed, there is always liquidity available for longs to close.
            _params.shareReserves -= YieldSpaceMath
                .calculateSharesOutGivenBondsIn(
                    _params.shareReserves,
                    _params.bondReserves,
                    uint256(netCurveTrade),
                    FixedPointMath.ONE_18.sub(_params.timeStretch),
                    _params.sharePrice,
                    _params.initialSharePrice
                );
        } else if (netCurveTrade < 0) {
            // It's possible that the exchange gets into a state where the
            // net curve trade can't be applied to the reserves. In particular,
            // this can happen if all of the liquidity is removed. We first
            // attempt to trade as much as possible on the curve, and then we
            // mark the remaining amount to the base volume.
            uint256 maxCurveTrade = _params.bondReserves.divDown(
                _params.initialSharePrice
            ) - _params.shareReserves;
            maxCurveTrade = uint256(-netCurveTrade) <= maxCurveTrade
                ? uint256(-netCurveTrade)
                : maxCurveTrade;
            _params.shareReserves += YieldSpaceMath
                .calculateSharesInGivenBondsOut(
                    _params.shareReserves,
                    _params.bondReserves,
                    maxCurveTrade,
                    FixedPointMath.ONE_18.sub(_params.timeStretch),
                    _params.sharePrice,
                    _params.initialSharePrice
                );
            _params.shareReserves += _params.shortBaseVolume.mulDivDown(
                uint256(-netCurveTrade) - maxCurveTrade,
                _params.shortsOutstanding.mulDown(_params.sharePrice)
            );
        }

        // Compute the net of the longs and shorts that will be traded flat
        // and apply this net to the reserves.
        int256 netFlatTrade = int256(
            _params.shortsOutstanding.mulDivDown(
                FixedPointMath.ONE_18 - _params.shortAverageTimeRemaining,
                _params.sharePrice
            )
        ) -
            int256(
                _params.longsOutstanding.mulDivDown(
                    FixedPointMath.ONE_18 - _params.longAverageTimeRemaining,
                    _params.sharePrice
                )
            );
        _params.shareReserves = uint256(
            int256(_params.shareReserves) + netFlatTrade
        );

        return _params.shareReserves;
    }

    /// @dev Calculates the proceeds in shares of closing a short position. This
    ///      takes into account the trading profits, the interest that was
    ///      earned by the short, and the amount of margin that was released
    ///      by closing the short. The math for the short's proceeds in base is
    ///      given by:
    ///
    ///      proceeds = dy - c * dz + (c1 - c0) * (dy / c0)
    ///               = dy - c * dz + (c1 / c0) * dy - dy
    ///               = (c1 / c0) * dy - c * dz
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
    /// @return shareProceeds The short proceeds in shares.
    function calculateShortProceeds(
        uint256 _bondAmount,
        uint256 _shareAmount,
        uint256 _openSharePrice,
        uint256 _closeSharePrice,
        uint256 _sharePrice
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
        if (bondFactor > _shareAmount) {
            // proceeds = (c1 / c0 * c) * dy - dz
            shareProceeds = bondFactor - _shareAmount;
        }
        return shareProceeds;
    }

    /// @dev Calculates the interest in shares earned by a short position. The
    ///      math for the short's interest in shares is given by:
    ///
    ///      interest = ((c1 / c0 - 1) * dy) / c
    ///               = (((c1 - c0) / c0) * dy) / c
    ///               = ((c1 - c0) / (c0 * c)) * dy
    ///
    ///      In the event that the interest is negative, we mark the interest
    ///      to zero.
    /// @param _bondAmount The amount of bonds underlying the closed short.
    /// @param _openSharePrice The share price at the short's open.
    /// @param _closeSharePrice The share price at the short's close.
    /// @param _sharePrice The current share price.
    /// @return shareInterest The short interest in shares.
    function calculateShortInterest(
        uint256 _bondAmount,
        uint256 _openSharePrice,
        uint256 _closeSharePrice,
        uint256 _sharePrice
    ) internal pure returns (uint256 shareInterest) {
        // If the interest is negative, we mark it to zero.
        if (_closeSharePrice > _openSharePrice) {
            // interest = dy * ((c1 - c0) / (c0 * c))
            shareInterest = _bondAmount.mulDivDown(
                _closeSharePrice - _openSharePrice,
                // We round up here do avoid overestimating the share interest.
                _openSharePrice.mulUp(_sharePrice)
            );
        }
        return shareInterest;
    }

    /// @dev Calculates the base volume of an open trade given the base amount,
    ///      the bond amount, and the time remaining. Since the base amount
    ///      takes into account backdating, we can't use this as our base
    ///      volume. Since we linearly interpolate between the base volume
    ///      and the bond amount as the time remaining goes from 1 to 0, the
    ///      base volume is can be determined as follows:
    ///
    ///      baseAmount = t * baseVolume + (1 - t) * bondAmount
    ///                               =>
    ///      baseVolume = (baseAmount - (1 - t) * bondAmount) / t
    /// @param _baseAmount The base exchanged in the open trade.
    /// @param _bondAmount The bonds exchanged in the open trade.
    /// @param _timeRemaining The time remaining in the position.
    /// @return baseVolume The calculated base volume.
    function calculateBaseVolume(
        uint256 _baseAmount,
        uint256 _bondAmount,
        uint256 _timeRemaining
    ) internal pure returns (uint256 baseVolume) {
        // If the time remaining is 0, the position has already matured and
        // doesn't have an impact on LP's ability to withdraw. This is a
        // pathological case that should never arise.
        if (_timeRemaining == 0) return 0;
        baseVolume = (
            _baseAmount.sub(
                (FixedPointMath.ONE_18.sub(_timeRemaining)).mulDown(_bondAmount)
            )
        ).divDown(_timeRemaining);
    }
}
