/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { YieldSpaceMath } from "contracts/libraries/YieldSpaceMath.sol";

// FIXME: The matrix of uses of flat+curve includes cases that should never
// occur. In particular, if isBondOut && t < 1 or isBondIn && t < 1, then the
// flat part refers to base tokens and the model doesn't make sense.
//
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
        // NOTE: This calculation is automatically scaled in the divDown operation
        uint256 t = _positionDuration.divDown(365 days);
        uint256 tau = t.divDown(_timeStretch);
        // ((y + s) / (mu * z)) ** -tau
        uint256 spotPrice = _initialSharePrice
            .mulDown(_shareReserves)
            .divDown(_bondReserves.add(_lpTotalSupply))
            .pow(tau);
        // (1 - p) / (p * t)
        return
            FixedPointMath.ONE_18.sub(spotPrice).divDown(spotPrice.mulDown(t));
    }

    // TODO: There is likely a more efficient formulation for when the rate is
    // based on the existing share and bond reserves.
    //
    /// @dev Calculates the bond reserves that will make the pool have a
    ///      specified APR.
    /// @param _shareReserves The pool's share reserves.
    /// @param _lpTotalSupply The pool's total supply of LP shares.
    /// @param _initialSharePrice The pool's initial share price.
    /// @param _apr The pool's APR.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
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
        // NOTE: This calculation is automatically scaled in the divDown operation
        uint256 t = _positionDuration.divDown(365 days);
        uint256 tau = t.divDown(_timeStretch);
        // (1 + apr * t) ** (1 / tau)
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
    /// @param _amountIn The amount of the asset that is provided.
    /// @param _timeRemaining The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @param _isBondOut A flag that specifies whether bonds are the asset being
    ///        received or the asset being provided.
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
        uint256 _timeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice,
        bool _isBondOut
    )
        internal
        pure
        returns (
            uint256 poolShareDelta,
            uint256 poolBondDelta,
            uint256 userDelta
        )
    {
        // TODO: See if this is actually true.
        //
        // This pricing model only supports the purchasing of bonds when
        // timeRemaining = 1.
        if (_isBondOut && _timeRemaining < 1) {
            revert Errors.HyperdriveMath_BaseWithNonzeroTime();
        }

        uint256 oneDivT = FixedPointMath.ONE_18.divDown(_timeStretch);

        if (_isBondOut) {
            // If bonds are being purchased, then the entire trade occurs on the
            // curved portion since t = 1.
            uint256 amountOut = YieldSpaceMath.calculateOutGivenIn(
                _shareReserves,
                _bondReserves,
                _bondReserveAdjustment,
                _amountIn,
                FixedPointMath.ONE_18,
                oneDivT,
                _sharePrice,
                _initialSharePrice,
                _isBondOut
            );
            return (_amountIn, amountOut, amountOut);
        } else {
            // Since we are trading bonds, it's possible that timeRemaining < 1.
            // We consider (1-timeRemaining)*amountIn of the bonds to be fully
            // matured and timeRemaining*amountIn of the bonds to be newly
            // minted. The fully matured bonds are redeemed one-to-one to base
            // (our result is given in shares, so we divide the one-to-one
            // redemption by the share price) and the newly minted bonds are
            // traded on a YieldSpace curve configured to timeRemaining = 1.
            uint256 flat = _amountIn
                .mulDown(FixedPointMath.ONE_18.sub(_timeRemaining))
                .divDown(_sharePrice);
            uint256 curveIn = _amountIn.mulDown(_timeRemaining);
            uint256 curveOut = YieldSpaceMath.calculateOutGivenIn(
                // Debit the share reserves by the flat trade.
                _shareReserves.sub(flat.divDown(_initialSharePrice)),
                // Credit the bond reserves by the flat trade.
                _bondReserves.add(flat),
                _bondReserveAdjustment,
                curveIn,
                FixedPointMath.ONE_18,
                oneDivT,
                _sharePrice,
                _initialSharePrice,
                _isBondOut
            );
            return (flat.add(curveOut), curveIn, flat.add(curveOut));
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
    /// @param _timeRemaining The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return poolShareDelta The delta that should be applied to the pool's
    ///         share reserves.
    /// @return poolBondDelta The delta that should be applied to the pool's
    ///         bond reserves.
    /// @return userDelta The amount of assets the user should receive.
    function calculateBaseInGivenBondsOut(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _bondReserveAdjustment,
        uint256 _amountOut,
        uint256 _timeRemaining,
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
            .mulDown(FixedPointMath.ONE_18.sub(_timeRemaining))
            .divDown(_sharePrice);
        uint256 curveOut = _amountOut.mulDown(_timeRemaining);
        uint256 oneDivT = FixedPointMath.ONE_18.divDown(_timeStretch);
        uint256 curveIn = YieldSpaceMath.calculateInGivenOut(
            // Credit the share reserves by the flat trade.
            _shareReserves.add(flat.divDown(_sharePrice)),
            // Debit the bond reserves by the flat trade.
            _bondReserves.sub(flat),
            _bondReserveAdjustment,
            curveOut,
            FixedPointMath.ONE_18,
            oneDivT,
            _sharePrice,
            _initialSharePrice,
            false
        );
        return (flat.add(curveIn), curveIn, flat.add(curveIn));
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
        // (d_z * l) / (z + b_y / c - b_x / c)
        return
            _shares.mulDown(_lpTotalSupply).divDown(
                _shareReserves.add(_shortsOutstanding.divDown(_sharePrice)).sub(
                    _longsOutstanding.divDown(_sharePrice)
                )
            );
    }

    // TODO: Use a withdrawal scheme that gives LPs exposure to the open trades
    //       that they facilitated.
    //
    /// @dev Calculates the amount of base shares released from burning a
    ///      a specified amount of LP shares from the pool.
    /// @param _shares The amount of LP shares burned from the pool.
    /// @param _shareReserves The pool's share reserves.
    /// @param _lpTotalSupply The pool's total supply of LP shares.
    /// @param _longsOutstanding The amount of long positions outstanding.
    /// @param _sharePrice The pool's share price.
    /// @return The amount of base shares released.
    function calculateSharesOutForLpSharesIn(
        uint256 _shares,
        uint256 _shareReserves,
        uint256 _lpTotalSupply,
        uint256 _longsOutstanding,
        uint256 _sharePrice
    ) internal pure returns (uint256) {
        // (z - b_x / c) * (d_l / l)
        return
            _shareReserves.sub(_longsOutstanding.divDown(_sharePrice)).mulDown(
                _shares.divDown(_lpTotalSupply)
            );
    }
}
