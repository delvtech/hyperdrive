/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

// FIXME
import "forge-std/console.sol";
import "test/utils/Lib.sol";

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { FixedPointMath } from "./FixedPointMath.sol";
import { YieldSpaceMath } from "./YieldSpaceMath.sol";

/// @author DELV
/// @title Hyperdrive
/// @notice Math for the Hyperdrive pricing model.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library HyperdriveMath {
    using FixedPointMath for uint256;

    // FIXME: Redocument this.
    //
    /// @dev Calculates the spot price without slippage of bonds in terms of base.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _initialSharePrice The initial share price as an 18 fixed-point value.
    /// @param _timeStretch The time stretch parameter as an 18 fixed-point value.
    /// @return spotPrice The spot price of bonds in terms of base as an 18 fixed-point value.
    function calculateSpotPrice(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _initialSharePrice,
        uint256 _timeStretch
    ) internal pure returns (uint256 spotPrice) {
        // (y / (mu * z)) ** -ts
        // ((mu * z) / y) ** ts
        spotPrice = YieldSpaceMath.BOND_CONVERSION_FACTOR.mulDown(
            _initialSharePrice
                .mulDivDown(
                    _shareReserves,
                    _bondReserves.mulDown(YieldSpaceMath.BOND_CONVERSION_FACTOR)
                )
                .pow(_timeStretch)
        );
    }

    // FIXME: Move this to `YieldSpaceMath` and rename it `calculateSpotRate`.
    //
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
    /// @param _initialSharePrice The pool's initial share price.
    /// @param _apr The pool's APR.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @return bondReserves The bond reserves (without adjustment) that make
    ///         the pool have a specified APR.
    function calculateInitialBondReserves(
        uint256 _shareReserves,
        uint256 _initialSharePrice,
        uint256 _apr,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 bondReserves) {
        // NOTE: Using divDown to convert to fixed point format.
        uint256 t = _positionDuration.divDown(365 days);
        uint256 tau = FixedPointMath.ONE_18.mulDown(_timeStretch);
        // mu * z * (1 + apr * t) ** (1 / tau)
        //
        // 1 / (1 + apr * t) == y_factor * ((mu * z) / (y * y_factor)) ** tau
        //
        // =>
        //
        // (1 / y_factor * (1 + apr * t)) ** (1 / tau) == (mu * z) / (y * y_factor)
        //
        // y = (mu * z) * (y_factor * (1 + apr * t)) ** (1 / tau) / y_factor
        return
            _initialSharePrice
                .mulDown(_shareReserves)
                .mulDown(
                    YieldSpaceMath
                        .BOND_CONVERSION_FACTOR
                        .mulDown(FixedPointMath.ONE_18 + _apr.mulDown(t))
                        .pow(FixedPointMath.ONE_18.divUp(tau))
                )
                .divDown(YieldSpaceMath.BOND_CONVERSION_FACTOR);
    }

    /// @dev Calculates the number of bonds a user will receive when opening a long position.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _shareAmount The amount of shares the user is depositing.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return bondReservesDelta The bonds paid by the reserves in the trade.
    function calculateOpenLong(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _shareAmount,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    )
        internal
        view
        returns (
            // FIXME: pure
            uint256
        )
    {
        // (time remaining)/(term length) is always 1 so we just use _timeStretch
        return
            YieldSpaceMath.calculateBondsOutGivenSharesIn(
                _shareReserves,
                _bondReserves,
                _shareAmount,
                FixedPointMath.ONE_18.sub(_timeStretch),
                _sharePrice,
                _initialSharePrice
            );
    }

    /// @dev Calculates the amount of shares a user will receive when closing a
    ///      long position.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _amountIn The amount of bonds the user is closing.
    /// @param _normalizedTimeRemaining The normalized time remaining of the
    ///        position.
    /// @param _timeStretch The time stretch parameter.
    /// @param _openSharePrice The share price at open.
    /// @param _closeSharePrice The share price at close.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The share price when the pool was deployed.
    /// @return shareReservesDelta The shares paid by the reserves in the trade.
    /// @return bondReservesDelta The bonds paid to the reserves in the trade.
    /// @return shareProceeds The shares that the user will receive.
    function calculateCloseLong(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _openSharePrice,
        uint256 _closeSharePrice,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    )
        internal
        pure
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
        shareProceeds = _amountIn.mulDivDown(
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining),
            _sharePrice
        );
        if (_normalizedTimeRemaining > 0) {
            // Calculate the curved part of the trade.
            bondReservesDelta = _amountIn.mulDown(_normalizedTimeRemaining);

            // (time remaining)/(term length) is always 1 so we just use _timeStretch
            shareReservesDelta = YieldSpaceMath.calculateSharesOutGivenBondsIn(
                _shareReserves,
                _bondReserves,
                bondReservesDelta,
                FixedPointMath.ONE_18.sub(_timeStretch),
                _sharePrice,
                _initialSharePrice
            );
            shareProceeds += shareReservesDelta;
        }

        // If there's net negative interest over the period, the result of close long
        // is adjusted down by the rate of negative interest. We always attribute negative
        // interest to the long since it's difficult or impossible to attribute
        // the negative interest to the short in practice.
        if (_openSharePrice > _closeSharePrice) {
            shareProceeds = shareProceeds.mulDivDown(
                _closeSharePrice,
                _openSharePrice
            );
            shareReservesDelta = shareReservesDelta.mulDivDown(
                _closeSharePrice,
                _openSharePrice
            );
        }
    }

    /// @dev Calculates the amount of shares that will be received given a
    ///      specified amount of bonds.
    /// @param _shareReserves The pool's share reserves
    /// @param _bondReserves The pool's bonds reserves.
    /// @param _amountIn The amount of bonds the user is providing.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return The shares paid by the reserves in the trade.
    function calculateOpenShort(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    ) internal pure returns (uint256) {
        // (time remaining)/(term length) is always 1 so we just use _timeStretch
        return
            YieldSpaceMath.calculateSharesOutGivenBondsIn(
                _shareReserves,
                _bondReserves,
                _amountIn,
                FixedPointMath.ONE_18.sub(_timeStretch),
                _sharePrice,
                _initialSharePrice
            );
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
        pure
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 sharePayment
        )
    {
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
        bondReservesDelta = _amountOut.mulDown(_normalizedTimeRemaining);
        if (bondReservesDelta > 0) {
            shareReservesDelta = YieldSpaceMath.calculateSharesInGivenBondsOut(
                _shareReserves,
                _bondReserves,
                bondReservesDelta,
                FixedPointMath.ONE_18.sub(_timeStretch),
                _sharePrice,
                _initialSharePrice
            );
            sharePayment += shareReservesDelta;
        }
    }

    struct MaxTradeParams {
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 longsOutstanding;
        uint256 timeStretch;
        uint256 sharePrice;
        uint256 initialSharePrice;
        uint256 minimumShareReserves;
    }

    /// @dev Calculates the maximum amount of shares a user can spend on buying
    ///      bonds before the spot crosses above a price of 1.
    /// @param _params Information about the market state and pool configuration
    ///        used to compute the maximum trade.
    /// @param _maxIterations The maximum number of iterations to perform before
    ///        returning the result.
    /// @return baseAmount The cost of the maximum long.
    /// @return bondAmount The maximum amount of longs that can be opened.
    function calculateMaxLong(
        MaxTradeParams memory _params,
        uint256 _maxIterations
    )
        internal
        view
        returns (
            // FIXME: pure
            uint256 baseAmount,
            uint256 bondAmount
        )
    {
        // We first solve for the maximum buy that is possible on the YieldSpace
        // curve. This will give us an upper bound on our maximum buy by giving
        // us the maximum buy that is possible without going into negative
        // interest territory. Hyperdrive has solvency requirements since it
        // mints longs on demand. If the maximum buy satisfies our solvency
        // checks, then we're done. If not, then we need to solve for the
        // maximum trade size iteratively.
        (uint256 dz, uint256 dy) = YieldSpaceMath.calculateMaxBuy(
            _params.shareReserves,
            _params.bondReserves,
            FixedPointMath.ONE_18 - _params.timeStretch,
            _params.sharePrice,
            _params.initialSharePrice
        );
        if (
            _params.shareReserves + dz >=
            (_params.longsOutstanding + dy).divDown(_params.sharePrice) +
                _params.minimumShareReserves
        ) {
            baseAmount = dz.mulDown(_params.sharePrice);
            bondAmount = dy;
            return (baseAmount, bondAmount);
        }

        // To make an initial guess for the iterative approximation, we consider
        // the solvency check to be the error that we want to reduce. The amount
        // the long buffer exceeds the share reserves is given by
        // (y_l + dy) / c - (z + dz). Since the error could be large, we'll use
        // the realized price of the trade instead of the spot price to
        // approximate the change in trade output. This gives us dy = c * 1/p * dz.
        // Substituting this into error equation and setting the error equal to
        // zero allows us to solve for the initial guess as:
        //
        // (y_l + c * 1/p * dz) / c + z_min - (z + dz) = 0
        //              =>
        // (1/p - 1) * dz = z - y_l/c - z_min
        //              =>
        // dz = (z - y_l/c - z_min) * (p / (p - 1))
        uint256 p = _params.sharePrice.mulDivDown(dz, dy);
        dz = (_params.shareReserves -
            _params.longsOutstanding.divDown(_params.sharePrice) -
            _params.minimumShareReserves).mulDivDown(
                p,
                FixedPointMath.ONE_18 - p
            );
        dy = YieldSpaceMath.calculateBondsOutGivenSharesIn(
            _params.shareReserves,
            _params.bondReserves,
            dz,
            FixedPointMath.ONE_18 - _params.timeStretch,
            _params.sharePrice,
            _params.initialSharePrice
        );

        // Our maximum long will be the largest trade size that doesn't fail
        // the solvency check.
        for (uint256 i = 0; i < _maxIterations; i++) {
            // If the approximation error is greater than zero and the solution
            // is the largest we've found so far, then we update our result.
            int256 approximationError = int256((_params.shareReserves + dz)) -
                int256(
                    (_params.longsOutstanding + dy).divDown(_params.sharePrice)
                ) -
                int256(_params.minimumShareReserves);
            if (
                approximationError > 0 &&
                dz.mulDown(_params.sharePrice) > baseAmount
            ) {
                baseAmount = dz.mulDown(_params.sharePrice);
                bondAmount = dy;
            }

            // Even though YieldSpace isn't linear, we can use a linear
            // approximation to get closer to the optimal solution. Our guess
            // should bring us close enough to the optimal point that we can
            // linearly approximate the change in error using the current spot
            // price.
            //
            // We can approximate the change in the trade output with respect to
            // trade size as dy' = c * (1/p) * dz'. Substituting this into our
            // error equation and setting the error equation equal to zero
            // allows us to solve for the trade size update:
            //
            // (y_l + dy + c * (1/p) * dz') / c + z_min - (z + dz + dz') = 0
            //                  =>
            // (1/p - 1) * dz' = (z + dz) - (y_l + dy) / c - z_min
            //                  =>
            // dz' = ((z + dz) - (y_l + dy) / c - z_min) * (p / (p - 1)).
            p = calculateSpotPrice(
                _params.shareReserves + dz,
                _params.bondReserves - dy,
                _params.initialSharePrice,
                _params.timeStretch
            );
            if (p >= FixedPointMath.ONE_18) {
                // If the spot price is greater than one and the error is
                // positive,
                break;
            }
            if (approximationError < 0) {
                uint256 delta = uint256(-approximationError).mulDivDown(
                    p,
                    FixedPointMath.ONE_18 - p
                );
                if (dz > delta) {
                    dz -= delta;
                } else {
                    dz = 0;
                }
            } else {
                dz += uint256(approximationError).mulDivDown(
                    p,
                    FixedPointMath.ONE_18 - p
                );
            }
            dy = YieldSpaceMath.calculateBondsOutGivenSharesIn(
                _params.shareReserves,
                _params.bondReserves,
                dz,
                FixedPointMath.ONE_18 - _params.timeStretch,
                _params.sharePrice,
                _params.initialSharePrice
            );
        }

        return (baseAmount, bondAmount);
    }

    // FIXME: This needs to be updated.
    //
    /// @dev Calculates the maximum amount of shares that can be used to open
    ///      shorts.
    /// @param _params Information about the market state and pool configuration
    ///        used to compute the maximum trade.
    /// @return The maximum amount of shares that can be used to open shorts.
    function calculateMaxShort(
        MaxTradeParams memory _params
    ) internal pure returns (uint256) {
        // The only constraint on the maximum short is that the share reserves
        // don't go negative and satisfy the solvency requirements. Thus, we can
        // set z = y_l/c + z_min and solve for the maximum short directly as:
        //
        // k = (c / mu) * (mu * (y_l / c + z_min)) ** (1 - tau) + y ** (1 - tau)
        //                         =>
        // y = (k - (c / mu) * (mu * (y_l / c + z_min)) ** (1 - tau)) ** (1 / (1 - tau)).
        uint256 t = FixedPointMath.ONE_18 - _params.timeStretch;
        uint256 priceFactor = _params.sharePrice.divDown(
            _params.initialSharePrice
        );
        uint256 k = YieldSpaceMath.modifiedYieldSpaceConstant(
            priceFactor,
            _params.initialSharePrice,
            _params.shareReserves,
            t,
            _params.bondReserves
        );
        uint256 innerFactor = (_params.initialSharePrice.mulDown(
            _params.longsOutstanding.divDown(_params.sharePrice)
        ) + _params.minimumShareReserves).pow(t);
        uint256 optimalBondReserves = (k - priceFactor.mulDown(innerFactor))
            .pow(FixedPointMath.ONE_18.divDown(t));

        // The optimal bond reserves imply a maximum short of dy = y - y0.
        return optimalBondReserves - _params.bondReserves;
    }

    struct PresentValueParams {
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 sharePrice;
        uint256 initialSharePrice;
        uint256 minimumShareReserves;
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
    ) internal view returns (uint256) {
        // Compute the net of the longs and shorts that will be traded on the
        // curve and apply this net to the reserves.
        console.log("calculatePresentValue: 1");
        int256 netCurveTrade = int256(
            _params.longsOutstanding.mulDown(_params.longAverageTimeRemaining)
        ) -
            int256(
                _params.shortsOutstanding.mulDown(
                    _params.shortAverageTimeRemaining
                )
            );
        console.log("calculatePresentValue: 2");
        if (netCurveTrade > 0) {
            // Apply the curve trade directly to the reserves. Unlike shorts,
            // the capital that backs longs is accounted for within the share
            // reserves (the capital backing shorts is taken out of the
            // reserves). This ensures that even if all the liquidity is
            // removed, there is always liquidity available for longs to close.
            console.log("calculatePresentValue: 3");
            _params.shareReserves -= YieldSpaceMath
                .calculateSharesOutGivenBondsIn(
                    _params.shareReserves,
                    _params.bondReserves,
                    uint256(netCurveTrade),
                    FixedPointMath.ONE_18.sub(_params.timeStretch),
                    _params.sharePrice,
                    _params.initialSharePrice
                );
            console.log("calculatePresentValue: 4");
        } else if (netCurveTrade < 0) {
            // It's possible that the exchange gets into a state where the
            // net curve trade can't be applied to the reserves. In particular,
            // this can happen if all of the liquidity is removed. We first
            // attempt to trade as much as possible on the curve, and then we
            // mark the remaining amount to the base volume. We can assume that
            // the outstanding long amount is zero when we apply the net curve
            // trade, so the only constraint is that the spot price cannot
            // exceed 1.
            console.log("calculatePresentValue: 5");
            (, uint256 maxCurveTrade) = YieldSpaceMath.calculateMaxBuy(
                _params.shareReserves,
                _params.bondReserves,
                FixedPointMath.ONE_18 - _params.timeStretch,
                _params.sharePrice,
                _params.initialSharePrice
            );
            console.log("calculatePresentValue: 6");
            maxCurveTrade = uint256(-netCurveTrade) <= maxCurveTrade
                ? uint256(-netCurveTrade)
                : maxCurveTrade;
            console.log("calculatePresentValue: 7");
            if (maxCurveTrade > 0) {
                _params.shareReserves += YieldSpaceMath
                    .calculateSharesInGivenBondsOut(
                        _params.shareReserves,
                        _params.bondReserves,
                        maxCurveTrade,
                        FixedPointMath.ONE_18.sub(_params.timeStretch),
                        _params.sharePrice,
                        _params.initialSharePrice
                    );
            }
            console.log("calculatePresentValue: 8");
            _params.shareReserves += _params.shortBaseVolume.mulDivDown(
                uint256(-netCurveTrade) - maxCurveTrade,
                _params.shortsOutstanding.mulDown(_params.sharePrice)
            );
            console.log("calculatePresentValue: 9");
        }

        // Compute the net of the longs and shorts that will be traded flat
        // and apply this net to the reserves.
        console.log("calculatePresentValue: 10");
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
        console.log("calculatePresentValue: 11");
        _params.shareReserves = uint256(
            int256(_params.shareReserves) + netFlatTrade
        );
        console.log("calculatePresentValue: 12");

        // The present value is the final share reserves minus the minimum share
        // reserves. This ensures that LP withdrawals won't include the minimum
        // share reserves.
        return _params.shareReserves - _params.minimumShareReserves;
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
