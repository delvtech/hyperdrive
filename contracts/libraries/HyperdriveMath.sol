/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { YieldSpaceMath } from "contracts/libraries/YieldSpaceMath.sol";

/// @author Delve
/// @title Hyperdrive
/// @notice Math for the Hyperdrive pricing model.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library HyperdriveMath {
    using FixedPointMath for uint256;

    /// @dev Calculates the APR from the pool's reserves.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _lpTotalSupply The pool's total supply of LP shares.
    /// @param _initialSharePrice The pool's initial share price.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @return apr The pool's APR.
    function calculateAPRFromReserves(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _lpTotalSupply,
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
            _lpTotalSupply,
            _initialSharePrice,
            annualizedTime,
            _timeStretch
        );

        // r = (1 - p) / (p * t)
        return
            FixedPointMath.ONE_18.sub(spotPrice).divDown(
                spotPrice.mulDown(annualizedTime)
            );
    }

    /// @dev Calculates the initial bond reserves assuming that the initial LP
    ///      receives LP shares amounting to c * z + y.
    /// @param _shareReserves The pool's share reserves.
    /// @param _sharePrice The pool's share price.
    /// @param _initialSharePrice The pool's initial share price.
    /// @param _apr The pool's APR.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @return bondReserves The bond reserves that make the pool have a
    ///         specified APR.
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
        uint256 tau = t.mulDown(_timeStretch);
        // mu * (1 + apr * t) ** (1 / tau) - c
        uint256 rhs = _initialSharePrice
            .mulDown(
                FixedPointMath.ONE_18.add(_apr.mulDown(t)).pow(
                    FixedPointMath.ONE_18.divDown(tau)
                )
            )
            .sub(_sharePrice);
        // (z / 2) * (mu * (1 + apr * t) ** (1 / tau) - c)
        return _shareReserves.divDown(2 * FixedPointMath.ONE_18).mulDown(rhs);
    }

    /// @dev Calculates the bond reserves that will make the pool have a
    ///      specified APR.
    /// @param _shareReserves The pool's share reserves.
    /// @param _lpTotalSupply The pool's total supply of LP shares.
    /// @param _initialSharePrice The pool's initial share price as an 18 fixed-point number.
    /// @param _apr The pool's APR as an 18 fixed-point number.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter as an 18 fixed-point number.
    /// @return bondReserves The bond reserves that make the pool have a
    ///         specified APR.
    function calculateBondReserves(
        uint256 _shareReserves,
        uint256 _lpTotalSupply,
        uint256 _initialSharePrice,
        uint256 _apr,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 bondReserves) {
        // Solving for (1 + r * t) ** (1 / tau) here. t is the normalized time remaining which in
        // this case is 1. Because bonds mature after the positionDuration, we need to scale the apr
        // to the proportion of a year of the positionDuration. tau = t / time_stretch, or just
        // 1 / time_stretch in this case.
        uint256 t = _positionDuration.divDown(365 days);
        uint256 tau = FixedPointMath.ONE_18.divDown(_timeStretch);
        uint256 interestFactor = FixedPointMath.ONE_18.add(_apr.mulDown(t)).pow(
            FixedPointMath.ONE_18.divDown(tau)
        );

        // mu * z * (1 + apr * t) ** (1 / tau)
        uint256 lhs = _initialSharePrice.mulDown(_shareReserves).mulDown(
            interestFactor
        );
        // mu * z * (1 + apr * t) ** (1 / tau) - l
        return lhs.sub(_lpTotalSupply);
    }

    /// @dev Calculates the amount of an asset that will be received given a
    ///      specified amount of the other asset given the current AMM reserves.
    /// @param _shareReserves The pool's share reserves
    /// @param _bondReserves The pool's bonds reserves.
    /// @param _bondReserveAdjustment The bond reserves are adjusted to improve
    ///        the capital efficiency of the AMM. Otherwise, the APR would be 0%
    ///        when share_reserves = bond_reserves, which would ensure that half
    ///        of the pool reserves couldn't be used to provide liquidity.
    /// @param _amountIn The amount to be traded. This quantity is denominated
    ///        in shares if bonds are being traded out and bonds if shares are
    ///        being traded out.
    /// @param _normalizedTimeRemaining The normalized amount of time remaining until maturity.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @param _isBaseIn A flag that specifies if the base asset is being provided.
    /// @return poolShareDelta The delta that should be applied to the pool's
    ///         share reserves.
    /// @return poolBondDelta The delta that should be applied to the pool's
    ///         bond reserves.
    /// @return userDelta The amount of assets the user should receive.
    function calculateOutGivenIn(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _bondReserveAdjustment,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice,
        bool _isBaseIn
    )
        internal
        pure
        returns (
            uint256 poolShareDelta,
            uint256 poolBondDelta,
            uint256 userDelta
        )
    {
        if (_isBaseIn) {
            // We consider (1 - timeRemaining) * amountIn of the bonds being
            // purchased to be fully matured and we use the remaining
            // timeRemaining * amountIn shares to purchase newly minted bonds on a
            // YieldSpace curve configured to timeRemaining = 1.

            // TODO: Revisit this assumption. It seems like LPs can bake this into the
            // fee schedule rather than adding a hidden fee.
            //
            // Calculate the curved part of the trade assuming that the flat part of
            // the trade was applied to the share and bond reserves.
            uint256 flat = _amountIn.mulDown(
                FixedPointMath.ONE_18.sub(_normalizedTimeRemaining)
            );

            _shareReserves = _shareReserves.add(flat);
            _bondReserves = _bondReserves.sub(flat.mulDown(_sharePrice));
            uint256 curveIn = _amountIn.mulDown(_normalizedTimeRemaining);
            uint256 curveOut = YieldSpaceMath.calculateOutGivenIn(
                _shareReserves,
                _bondReserves,
                _bondReserveAdjustment,
                curveIn,
                FixedPointMath.ONE_18.sub(_timeStretch),
                _sharePrice,
                _initialSharePrice,
                _isBaseIn
            );
            return (curveIn, curveOut, flat.mulDown(_sharePrice).add(curveOut));
        } else {
            // We consider (1 - timeRemaining) * amountIn of the bonds to be fully
            // matured and timeRemaining * amountIn of the bonds to be newly
            // minted. The fully matured bonds are redeemed one-to-one to base
            // (our result is given in shares, so we divide the one-to-one
            // redemption by the share price) and the newly minted bonds are
            // traded on a YieldSpace curve configured to timeRemaining = 1.
            uint256 flat = _amountIn
                .mulDown(FixedPointMath.ONE_18.sub(_normalizedTimeRemaining))
                .divDown(_sharePrice);

            // TODO: Revisit this assumption. It seems like LPs can bake this into the
            // fee schedule rather than adding a hidden fee.
            //
            // Calculate the curved part of the trade assuming that the flat part of
            // the trade was applied to the share and bond reserves.
            _shareReserves = _shareReserves.sub(flat);
            _bondReserves = _bondReserves.add(flat.mulDown(_sharePrice));
            uint256 curveIn = _amountIn
                .mulDown(_normalizedTimeRemaining)
                .divDown(_sharePrice);
            uint256 curveOut = YieldSpaceMath.calculateOutGivenIn(
                _shareReserves,
                _bondReserves,
                _bondReserveAdjustment,
                curveIn,
                FixedPointMath.ONE_18.sub(_timeStretch),
                _sharePrice,
                _initialSharePrice,
                _isBaseIn
            );
            uint256 shareDelta = flat.add(curveOut);
            return (shareDelta, curveIn, shareDelta);
        }
    }

    /// @dev Calculates the amount of base that must be provided to receive a
    ///      specified amount of bonds.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bonds reserves.
    /// @param _bondReserveAdjustment The bond reserves are adjusted to improve
    ///        the capital efficiency of the AMM. Otherwise, the APR would be 0%
    ///        when share_reserves = bond_reserves, which would ensure that half
    ///        of the pool reserves couldn't be used to provide liquidity.
    /// @param _amountOut The amount of the asset that is received.
    /// @param _normalizedTimeRemaining The amount of time remaining until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return poolShareDelta The delta that should be applied to the pool's
    ///         share reserves.
    /// @return poolBondDelta The delta that should be applied to the pool's
    ///         bond reserves.
    /// @return userDelta The amount of assets the user should receive.
    function calculateSharesInGivenBondsOut(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _bondReserveAdjustment,
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    )
        internal
        pure
        returns (
            uint256 poolShareDelta,
            uint256 poolBondDelta,
            uint256 userDelta
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
        uint256 flat = _amountOut
            .mulDown(FixedPointMath.ONE_18.sub(_normalizedTimeRemaining))
            .divDown(_sharePrice);
        uint256 curveOut = _amountOut.mulDown(_normalizedTimeRemaining).divDown(
            _sharePrice
        );

        // TODO: Revisit this assumption. It seems like LPs can bake this into the
        // fee schedule rather than adding a hidden fee.
        //
        // Calculate the curved part of the trade assuming that the flat part of
        // the trade was applied to the share and bond reserves.
        _shareReserves = _shareReserves.add(flat);
        _bondReserves = _bondReserves.sub(flat.mulDown(_sharePrice));
        uint256 curveIn = 0;
        if (curveOut > 0) {
            curveIn = YieldSpaceMath.calculateInGivenOut(
                _shareReserves,
                _bondReserves,
                _bondReserveAdjustment,
                curveOut,
                FixedPointMath.ONE_18.sub(_timeStretch),
                _sharePrice,
                _initialSharePrice,
                false
            );
        }
        return (flat.add(curveIn), curveOut, flat.add(curveIn));
    }

    /// @dev Calculates the spot price without slippage of bonds in terms of shares.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _lpTotalSupply The pool's total supply of LP shares.
    /// @param _initialSharePrice The initial share price as an 18 fixed-point value.
    /// @param _normalizedTimeRemaining The normalized amount of time remaining until maturity.
    /// @param _timeStretch The time stretch parameter as an 18 fixed-point value.
    /// @return spotPrice The spot price of bonds in terms of shares as an 18 fixed-point value.
    function calculateSpotPrice(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _lpTotalSupply,
        uint256 _initialSharePrice,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch
    ) internal pure returns (uint256 spotPrice) {
        // ((y + s) / (mu * z)) ** -tau
        uint256 tau = _normalizedTimeRemaining.divDown(_timeStretch);
        spotPrice = _initialSharePrice
            .mulDown(_shareReserves)
            .divDown(_bondReserves.add(_lpTotalSupply))
            .pow(tau);
    }

    /// @dev Calculates the fees for the curve portion of hyperdrive calcOutGivenIn
    /// @param _amountIn The given amount in, either in terms of shares or bonds.
    /// @param _normalizedTimeRemaining The normalized amount of time until maturity.
    /// @param _spotPrice The price without slippage of bonds in terms of shares.
    /// @param _sharePrice The current price of shares in terms of base.
    /// @param _curveFeePercent The curve fee parameter.
    /// @param _flatFeePercent The flat fee parameter.
    /// @param _isBaseIn If the user will supply base.
    /// @return curveFee The fee amount to charge.
    /// @return flatFee The fee amount to charge.
    function calculateFeesOutGivenIn(
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice,
        uint256 _curveFeePercent,
        uint256 _flatFeePercent,
        bool _isBaseIn
    ) internal pure returns (uint256 curveFee, uint256 flatFee) {
        uint256 curveIn = _amountIn.mulDown(_normalizedTimeRemaining);
        if (_isBaseIn) {
            // curve fee = ((1 / p) - 1) * phi * c * d_z * t
            uint256 _pricePart = (FixedPointMath.ONE_18.divDown(_spotPrice))
                .sub(FixedPointMath.ONE_18);
            curveFee = _pricePart
                .mulDown(_curveFeePercent)
                .mulDown(_sharePrice)
                .mulDown(curveIn)
                .mulDown(_normalizedTimeRemaining);
            // flat fee = c * d_z * (1 - t)
            uint256 flat = _amountIn.mulDown(
                FixedPointMath.ONE_18.sub(_normalizedTimeRemaining)
            );
            flatFee = (flat.mulDown(_sharePrice).mulDown(_flatFeePercent));
        } else {
            // 'bond' in
            // flat fee = (1 - p) * phi * d_y * t
            uint256 _pricePart = (FixedPointMath.ONE_18.sub(_spotPrice));
            curveFee = _pricePart
                .mulDown(_curveFeePercent)
                .mulDown(curveIn)
                .mulDown(_normalizedTimeRemaining);
            // curve fee = d_y * (1 - t)
            uint256 flat = _amountIn.mulDown(
                FixedPointMath.ONE_18.sub(_normalizedTimeRemaining)
            );
            flatFee = (flat.mulDown(_flatFeePercent));
        }
    }

    /// @dev Calculates the fees for the curve portion of hyperdrive calcInGivenOut
    /// @param _amountOut The given amount out, either in terms of shares or bonds.
    /// @param _normalizedTimeRemaining The normalized amount of time until maturity.
    /// @param _spotPrice The price without slippage of bonds in terms of shares.
    /// @param _sharePrice The current price of shares in terms of base.
    /// @param _curveFeePercent The curve fee parameter.
    /// @param _flatFeePercent The flat fee parameter.
    /// @param _isBaseOut If the user will receive base.
    /// @return curveFee The fee amount to charge.
    /// @return flatFee The fee amount to charge.
    function calculateFeesInGivenOut(
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice,
        uint256 _curveFeePercent,
        uint256 _flatFeePercent,
        bool _isBaseOut
    ) internal pure returns (uint256 curveFee, uint256 flatFee) {
        uint256 curveOut = _amountOut.mulDown(_normalizedTimeRemaining);
        if (_isBaseOut) {
            // curve fee = ((1 / p) - 1) * phi * c * d_z
            uint256 _pricePart = (FixedPointMath.ONE_18.divDown(_spotPrice))
                .sub(FixedPointMath.ONE_18);
            curveFee = _pricePart
                .mulDown(_curveFeePercent)
                .mulDown(curveOut)
                .mulDown(_sharePrice)
                .mulDown(_normalizedTimeRemaining);
            // flat fee = c * d_z * (1 - t)
            uint256 flat = _amountOut.mulDown(
                FixedPointMath.ONE_18.sub(_normalizedTimeRemaining)
            );
            flatFee = (flat.mulDown(_sharePrice).mulDown(_flatFeePercent));
        } else {
            // bonds out
            // curve fee = (1 - p) * phi * d_y * t
            uint256 _pricePart = FixedPointMath.ONE_18.sub(_spotPrice);
            curveFee = _pricePart
                .mulDown(_curveFeePercent)
                .mulDown(curveOut)
                .mulDown(_normalizedTimeRemaining);
            // flat fee = d_y * (1 - t)
            uint256 flat = _amountOut.mulDown(
                FixedPointMath.ONE_18.sub(_normalizedTimeRemaining)
            );
            flatFee = (flat.mulDown(_flatFeePercent));
        }
    }

    // TODO: Use an allocation scheme that doesn't punish early LPs.
    //
    /// @dev Calculates the amount of LP shares that should be awarded for
    ///      supplying a specified amount of base shares to the pool.
    /// @param _shares The amount of base shares supplied to the pool.
    /// @param _shareReserves The pool's share reserves.
    /// @param _lpTotalSupply The pool's total supply of LP shares.
    /// @param _longsOutstanding The amount of long positions outstanding.
    /// @param _shortsOutstanding The amount of short positions outstanding.
    /// @param _sharePrice The pool's share price.
    /// @return The amount of LP shares awarded.
    function calculateLpSharesOutForSharesIn(
        uint256 _shares,
        uint256 _shareReserves,
        uint256 _lpTotalSupply,
        uint256 _longsOutstanding,
        uint256 _shortsOutstanding,
        uint256 _sharePrice
    ) internal pure returns (uint256) {
        // (dz * l) / (z + b_y / c - b_x / c)
        return
            _shares.mulDown(_lpTotalSupply).divDown(
                _shareReserves.add(_shortsOutstanding.divDown(_sharePrice)).sub(
                    _longsOutstanding.divDown(_sharePrice)
                )
            );
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
        // (z - b_x / c) * (dl / l)
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
