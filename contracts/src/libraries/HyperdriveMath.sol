/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Errors } from "./Errors.sol";
import { FixedPointMath } from "./FixedPointMath.sol";
import { YieldSpaceMath } from "./YieldSpaceMath.sol";

/// @author Delve
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
    /// @param _amountIn The amount of shares the user is depositing.
    /// @param _normalizedTimeRemaining The amount of time remaining until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return curveIn The input amount for the curve trade (denominated in shares).
    /// @return curveOut The output amount for the curve trade (denominated in bonds).
    /// @return flat The flat amount (denominated in bonds).
    function calculateOpenLong(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    ) internal pure returns (uint256 curveIn, uint256 curveOut, uint256 flat) {
        // Calculate the flat part of the trade.
        flat = _amountIn.mulDown(
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining)
        );
        curveIn = _amountIn.mulDown(_normalizedTimeRemaining);
        // (time remaining)/(term length) is always 1 so we just use _timeStretch
        curveOut = YieldSpaceMath.calculateBondsOutGivenSharesIn(
            _shareReserves,
            _bondReserves,
            curveIn,
            FixedPointMath.ONE_18.sub(_timeStretch),
            _sharePrice,
            _initialSharePrice
        );
        return (curveIn, curveOut, flat);
    }

    /// @dev Calculates the amount of shares a user will receive when closing a
    ///      long position.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _amountIn The amount of bonds the user is closing.
    /// @param _normalizedTimeRemaining The normalized time remaining of the
    ///        position.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return curveIn The input amount for the curve trade (denominated in bonds).
    /// @return curveOut The output amount for the curve trade (denominated in shares).
    /// @return flat The flat amount (denominated in shares).
    function calculateCloseLong(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    ) internal pure returns (uint256 curveIn, uint256 curveOut, uint256 flat) {
        // We consider (1 - timeRemaining) * amountIn of the bonds to be fully
        // matured and timeRemaining * amountIn of the bonds to be newly
        // minted. The fully matured bonds are redeemed one-to-one to base
        // (our result is given in shares, so we divide the one-to-one
        // redemption by the share price) and the newly minted bonds are
        // traded on a YieldSpace curve configured to timeRemaining = 1.
        flat = _amountIn
            .mulDown(FixedPointMath.ONE_18.sub(_normalizedTimeRemaining))
            .divDown(_sharePrice);

        // If there's net negative interest over the period the flat redemption amount
        // is reduced.
        if (_initialSharePrice > _sharePrice) {
            flat = (flat.mulUp(_sharePrice)).divDown(_initialSharePrice);
        }

        if (_normalizedTimeRemaining > 0) {
            // Calculate the curved part of the trade.
            curveIn = _amountIn.mulDown(_normalizedTimeRemaining);
            // (time remaining)/(term length) is always 1 so we just use _timeStretch
            curveOut = YieldSpaceMath.calculateSharesOutGivenBondsIn(
                _shareReserves,
                _bondReserves,
                curveIn,
                FixedPointMath.ONE_18.sub(_timeStretch),
                _sharePrice,
                _initialSharePrice
            );
        }
        return (curveIn, curveOut, flat);
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
    /// @return curveIn The input amount for the curve trade (denominated in bonds).
    /// @return curveOut The output amount for the curve trade (denominated in shares).
    /// @return flat The flat amount (denominated in shares).
    function calculateOpenShort(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    ) internal pure returns (uint256 curveIn, uint256 curveOut, uint256 flat) {
        // Calculate the flat part of the trade.
        flat = _amountIn
            .mulDown(FixedPointMath.ONE_18.sub(_normalizedTimeRemaining))
            .divDown(_sharePrice);
        // Calculate the curved part of the trade.
        curveIn = _amountIn.mulDown(_normalizedTimeRemaining).divDown(
            _sharePrice
        );
        // (time remaining)/(term length) is always 1 so we just use _timeStretch
        curveOut = YieldSpaceMath.calculateSharesOutGivenBondsIn(
            _shareReserves,
            _bondReserves,
            curveIn,
            FixedPointMath.ONE_18.sub(_timeStretch),
            _sharePrice,
            _initialSharePrice
        );
        return (curveIn, curveOut, flat);
    }

    /// @dev Calculates the amount of base that a user will receive when closing a short position
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bonds reserves.
    /// @param _amountOut The amount of the asset that is received.
    /// @param _normalizedTimeRemaining The amount of time remaining until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return curveIn The input amount for the curve trade (denominated in shares).
    /// @return curveOut The output amount for the curve trade (denominated in bonds).
    /// @return flat The flat amount (denominated in shares).
    function calculateCloseShort(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    ) internal pure returns (uint256 curveIn, uint256 curveOut, uint256 flat) {
        // Since we are buying bonds, it's possible that timeRemaining < 1.
        // We consider (1-timeRemaining)*amountOut of the bonds being
        // purchased to be fully matured and timeRemaining*amountOut of the
        // bonds to be newly minted. The fully matured bonds are redeemed
        // one-to-one to base (our result is given in shares, so we divide
        // the one-to-one redemption by the share price) and the newly
        // minted bonds are traded on a YieldSpace curve configured to
        // timeRemaining = 1.
        flat = _amountOut
            .mulDown(FixedPointMath.ONE_18.sub(_normalizedTimeRemaining))
            .divDown(_sharePrice);

        if (_normalizedTimeRemaining > 0) {
            curveOut = _amountOut.mulDown(_normalizedTimeRemaining);
            // Calculate the curved part of the trade.
            curveIn = YieldSpaceMath.calculateSharesInGivenBondsOut(
                _shareReserves,
                _bondReserves,
                _amountOut,
                FixedPointMath.ONE_18.sub(_timeStretch),
                _sharePrice,
                _initialSharePrice
            );
        }

        return (curveIn, curveOut, flat);
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

    /// @dev Computes the LP allocation adjustment for a position. This is used
    ///      to accurately account for the duration risk that LPs take on when
    ///      adding liquidity so that LP shares can be rewarded fairly.
    /// @param _positionsOutstanding The position balance outstanding.
    /// @param _baseVolume The base volume created by opening the positions.
    /// @param _averageTimeRemaining The average time remaining of the positions.
    /// @param _sharePrice The pool's share price.
    /// @return adjustment The allocation adjustment.
    function calculateLpAllocationAdjustment(
        uint256 _positionsOutstanding,
        uint256 _baseVolume,
        uint256 _averageTimeRemaining,
        uint256 _sharePrice
    ) internal pure returns (uint256 adjustment) {
        // baseAdjustment = t * _baseVolume + (1 - t) * _positionsOutstanding
        adjustment = (_averageTimeRemaining.mulDown(_baseVolume)).add(
            (FixedPointMath.ONE_18.sub(_averageTimeRemaining)).mulDown(
                _positionsOutstanding
            )
        );
        // adjustment = baseAdjustment / c
        adjustment = adjustment.divDown(_sharePrice);
    }

    /// @dev Calculates the amount of base shares released from burning a
    ///      a specified amount of LP shares from the pool.
    /// @param _shares The amount of LP shares burned from the pool.
    /// @param _shareReserves The pool's share reserves.
    /// @param _lpTotalSupply The pool's total supply of LP shares.
    /// @param _longsOutstanding The amount of longs that haven't been closed.
    /// @param _shortsOutstanding The amount of shorts that haven't been closed.
    /// @param _sharePrice The pool's share price.
    /// @return shares The amount of base shares released.
    /// @return longWithdrawalShares The amount of long withdrawal shares
    ///         received.
    /// @return shortWithdrawalShares The amount of short withdrawal shares
    ///         received.
    function calculateOutForLpSharesIn(
        uint256 _shares,
        uint256 _shareReserves,
        uint256 _lpTotalSupply,
        uint256 _longsOutstanding,
        uint256 _shortsOutstanding,
        uint256 _sharePrice
    )
        internal
        pure
        returns (
            uint256 shares,
            uint256 longWithdrawalShares,
            uint256 shortWithdrawalShares
        )
    {
        // dl / l
        uint256 poolFactor = _shares.divDown(_lpTotalSupply);
        // (z - o_l / c) * (dl / l)
        shares = _shareReserves
            .sub(_longsOutstanding.divDown(_sharePrice))
            .mulDown(poolFactor);
        // longsOutstanding * (dl / l)
        longWithdrawalShares = _longsOutstanding.mulDown(poolFactor);
        // shortsOutstanding * (dl / l)
        shortWithdrawalShares = _shortsOutstanding.mulDown(poolFactor);
        return (shares, longWithdrawalShares, shortWithdrawalShares);
    }
}
