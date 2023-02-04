/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { HyperdriveError } from "contracts/libraries/Errors.sol";
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
    /// @param shareReserves The pool's share reserves.
    /// @param bondReserves The pool's bond reserves.
    /// @param lpTotalSupply The pool's total supply of LP shares.
    /// @param initialSharePrice The pool's initial share price.
    /// @param positionDuration The amount of time until maturity in seconds.
    /// @param timeStretch The time stretch parameter.
    /// @param apr The pool's APR.
    function calculateAPRFromReserves(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 lpTotalSupply,
        uint256 initialSharePrice,
        uint256 positionDuration,
        uint256 timeStretch
    ) internal pure returns (uint256 apr) {
        uint256 t = positionDuration.divDown(365 days * FixedPointMath.ONE_18);
        uint256 tau = t.divDown(timeStretch);
        // ((y + s) / (mu * z)) ** -tau
        uint256 spotPrice = initialSharePrice
            .mulDown(shareReserves)
            .divDown(bondReserves.add(lpTotalSupply))
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
    /// @param shareReserves The pool's share reserves.
    /// @param lpTotalSupply The pool's total supply of LP shares.
    /// @param initialSharePrice The pool's initial share price.
    /// @param apr The pool's APR.
    /// @param positionDuration The amount of time until maturity in seconds.
    /// @param timeStretch The time stretch parameter.
    /// @return bondReserves The bond reserves that make the pool have a
    ///         specified APR.
    function calculateBondReserves(
        uint256 shareReserves,
        uint256 lpTotalSupply,
        uint256 initialSharePrice,
        uint256 apr,
        uint256 positionDuration,
        uint256 timeStretch
    ) internal pure returns (uint256 bondReserves) {
        uint256 t = positionDuration.divDown(365 days * FixedPointMath.ONE_18);
        uint256 tau = t.divDown(timeStretch);
        // (1 + apr * t) ** (1 / tau)
        uint256 interestFactor = FixedPointMath.ONE_18.add(apr.mulDown(t)).pow(
            FixedPointMath.ONE_18.divDown(tau)
        );
        // mu * z * (1 + apr * t) ** (1 / tau)
        uint256 lhs = initialSharePrice.mulDown(shareReserves).mulDown(
            interestFactor
        );
        // mu * z * (1 + apr * t) ** (1 / tau) - s
        return lhs.sub(lpTotalSupply);
    }

    /// @dev Calculates the amount of an asset that will be received given a
    ///      specified amount of the other asset given the current AMM reserves.
    /// @param shareReserves The pool's share reserves
    /// @param bondReserves The pool's bonds reserves.
    /// @param bondReserveAdjustment The bond reserves are adjusted to improve
    ///        the capital efficiency of the AMM. Otherwise, the APR would be 0%
    ///        when share_reserves = bond_reserves, which would ensure that half
    ///        of the pool reserves couldn't be used to provide liquidity.
    /// @param amountIn The amount of the asset that is provided.
    /// @param timeRemaining The amount of time until maturity in seconds.
    /// @param timeStretch The time stretch parameter.
    /// @param sharePrice The share price.
    /// @param initialSharePrice The initial share price.
    /// @param isBondOut A flag that specifies whether bonds are the asset being
    ///        received or the asset being provided.
    /// @return poolShareDelta The delta that should be applied to the pool's
    ///         share reserves.
    /// @return poolBondDelta The delta that should be applied to the pool's
    ///         bond reserves.
    /// @return userDelta The amount of assets the user should receive.
    function calculateOutGivenIn(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 bondReserveAdjustment,
        uint256 amountIn,
        uint256 timeRemaining,
        uint256 timeStretch,
        uint256 sharePrice,
        uint256 initialSharePrice,
        bool isBondOut
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
        if (isBondOut && timeRemaining < 1) {
            revert HyperdriveError.HyperdriveMath_BaseWithNonzeroTime();
        }
        if (isBondOut) {
            // If bonds are being purchased, then the entire trade occurs on the
            // curved portion since t = 1.
            uint256 amountOut = YieldSpaceMath.calculateOutGivenIn(
                shareReserves,
                bondReserves,
                bondReserveAdjustment,
                amountIn,
                FixedPointMath.ONE_18,
                timeStretch,
                sharePrice,
                initialSharePrice,
                isBondOut
            );
            return (amountIn, amountOut, amountOut);
        } else {
            // Since we are trading bonds, it's possible that timeRemaining < 1.
            // We consider (1-timeRemaining)*amountIn of the bonds to be fully
            // matured and timeRemaining*amountIn of the bonds to be newly
            // minted. The fully matured bonds are redeemed one-to-one to base
            // (our result is given in shares, so we divide the one-to-one
            // redemption by the share price) and the newly minted bonds are
            // traded on a YieldSpace curve configured to timeRemaining = 1.
            uint256 flat = amountIn
                .mulDown(FixedPointMath.ONE_18.sub(timeRemaining))
                .divDown(sharePrice);
            uint256 curveIn = amountIn.mulDown(timeRemaining);
            uint256 curveOut = YieldSpaceMath.calculateOutGivenIn(
                // Debit the share reserves by the flat trade.
                shareReserves.sub(flat.divDown(initialSharePrice)),
                // Credit the bond reserves by the flat trade.
                bondReserves.add(flat),
                bondReserveAdjustment,
                curveIn,
                FixedPointMath.ONE_18,
                timeStretch,
                sharePrice,
                initialSharePrice,
                isBondOut
            );
            return (flat.add(curveOut), curveIn, flat.add(curveOut));
        }
    }

    /// @dev Calculates the amount of base that must be provided to receive a
    ///      specified amount of bonds.
    /// @param shareReserves The pool's share reserves.
    /// @param bondReserves The pool's bonds reserves.
    /// @param bondReserveAdjustment The bond reserves are adjusted to improve
    ///        the capital efficiency of the AMM. Otherwise, the APR would be 0%
    ///        when share_reserves = bond_reserves, which would ensure that half
    ///        of the pool reserves couldn't be used to provide liquidity.
    /// @param amountOut The amount of the asset that is received.
    /// @param timeRemaining The amount of time until maturity in seconds.
    /// @param timeStretch The time stretch parameter.
    /// @param sharePrice The share price.
    /// @param initialSharePrice The initial share price.
    /// @return poolShareDelta The delta that should be applied to the pool's
    ///         share reserves.
    /// @return poolBondDelta The delta that should be applied to the pool's
    ///         bond reserves.
    /// @return userDelta The amount of assets the user should receive.
    function calculateInGivenOut(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 bondReserveAdjustment,
        uint256 amountOut,
        uint256 timeRemaining,
        uint256 timeStretch,
        uint256 sharePrice,
        uint256 initialSharePrice
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
        uint256 flat = amountOut
            .mulDown(FixedPointMath.ONE_18.sub(timeRemaining))
            .divDown(sharePrice);
        uint256 curveOut = amountOut.mulDown(timeRemaining);
        uint256 curveIn = YieldSpaceMath.calculateInGivenOut(
            // Credit the share reserves by the flat trade.
            shareReserves.add(flat.divDown(sharePrice)),
            // Debit the bond reserves by the flat trade.
            bondReserves.sub(flat),
            bondReserveAdjustment,
            curveOut,
            FixedPointMath.ONE_18,
            timeStretch,
            sharePrice,
            initialSharePrice,
            false
        );
        return (flat.add(curveIn), curveIn, flat.add(curveIn));
    }
}
