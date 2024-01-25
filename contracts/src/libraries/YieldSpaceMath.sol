/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { FixedPointMath, ONE } from "./FixedPointMath.sol";
import { HyperdriveMath } from "./HyperdriveMath.sol";

/// @author DELV
/// @title YieldSpaceMath
/// @notice Math for the YieldSpace pricing model.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
///
/// @dev It is advised for developers to attain the pre-requisite knowledge
///      of how this implementation works on the mathematical level. This
///      excerpt attempts to document this pre-requisite knowledge explaining
///      the underpinning mathematical concepts in an understandable manner and
///      relating it directly to the code implementation.
///      This implementation is based on a paper called "YieldSpace with Yield
///      Bearing Vaults" or more casually "Modified YieldSpace". It can be
///      found at the following link.
///
///      https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw?view
///
///      That paper builds on the original YieldSpace paper, "YieldSpace:
///      An Automated Liquidity Provider for Fixed Yield Tokens". It can be
///      found at the following link:
///
///      https://yieldprotocol.com/YieldSpace.pdf
library YieldSpaceMath {
    using FixedPointMath for uint256;

    /// @dev Calculates the amount of bonds a user will receive from the pool by
    ///      providing a specified amount of shares. We underestimate the amount
    ///      of bonds out.
    /// @param ze The effective share reserves.
    /// @param y The bond reserves.
    /// @param dz The amount of shares paid to the pool.
    /// @param t The time elapsed since the term's start.
    /// @param c The vault share price.
    /// @param mu The initial vault share price.
    /// @return The amount of bonds the trader receives.
    function calculateBondsOutGivenSharesInDown(
        uint256 ze,
        uint256 y,
        uint256 dz,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // NOTE: We round k up to make the rhs of the equation larger.
        //
        // k = (c / µ) * (µ * ze)^(1 - t) + y^(1 - t)
        uint256 k = kUp(ze, y, t, c, mu);

        // NOTE: We round ze down to make the rhs of the equation larger.
        //
        //  (µ * (ze + dz))^(1 - t)
        ze = mu.mulDown(ze + dz).pow(t);
        //  (c / µ) * (µ * (ze + dz))^(1 - t)
        ze = c.mulDivDown(ze, mu);

        // NOTE: We round _y up to make the rhs of the equation larger.
        //
        // (k - (c / µ) * (µ * (ze + dz))^(1 - t))^(1 / (1 - t))
        uint256 _y = k - ze;
        if (_y >= ONE) {
            // Rounding up the exponent results in a larger result.
            _y = _y.pow(ONE.divUp(t));
        } else {
            // Rounding down the exponent results in a larger result.
            _y = _y.pow(ONE.divDown(t));
        }

        // Δy = y - (k - (c / µ) * (µ * (ze + dz))^(1 - t))^(1 / (1 - t))
        return y - _y;
    }

    /// @dev Calculates the amount of shares a user must provide the pool to
    ///      receive a specified amount of bonds. We overestimate the amount of
    ///      shares in.
    /// @param ze The effective share reserves.
    /// @param y The bond reserves.
    /// @param dy The amount of bonds paid to the trader.
    /// @param t The time elapsed since the term's start.
    /// @param c The vault share price.
    /// @param mu The initial vault share price.
    /// @return The amount of shares the trader pays.
    function calculateSharesInGivenBondsOutUp(
        uint256 ze,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // NOTE: We round k up to make the lhs of the equation larger.
        //
        // k = (c / µ) * (µ * ze)^(1 - t) + y^(1 - t)
        uint256 k = kUp(ze, y, t, c, mu);

        // (y - dy)^(1 - t)
        y = (y - dy).pow(t);

        // NOTE: We round _z up to make the lhs of the equation larger.
        //
        // ((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))
        uint256 _z = (k - y).mulDivUp(mu, c);
        if (_z >= ONE) {
            // Rounding up the exponent results in a larger result.
            _z = _z.pow(ONE.divUp(t));
        } else {
            // Rounding down the exponent results in a larger result.
            _z = _z.pow(ONE.divDown(t));
        }
        // ((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        _z = _z.divUp(mu);

        // Δz = (((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ - ze
        return _z - ze;
    }

    /// @dev Calculates the amount of shares a user must provide the pool to
    ///      receive a specified amount of bonds. We underestimate the amount of
    ///      shares in.
    /// @param ze The effective share reserves.
    /// @param y The bond reserves.
    /// @param dy The amount of bonds paid to the trader.
    /// @param t The time elapsed since the term's start.
    /// @param c The vault share price.
    /// @param mu The initial vault share price.
    /// @return The amount of shares the user pays.
    function calculateSharesInGivenBondsOutDown(
        uint256 ze,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // NOTE: We round k down to make the lhs of the equation smaller.
        //
        // k = (c / µ) * (µ * ze)^(1 - t) + y^(1 - t)
        uint256 k = kDown(ze, y, t, c, mu);

        // (y - dy)^(1 - t)
        y = (y - dy).pow(t);

        // NOTE: We round _z down to make the lhs of the equation smaller.
        //
        // _z = ((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))
        uint256 _z = (k - y).mulDivDown(mu, c);
        if (_z >= ONE) {
            // Rounding down the exponent results in a smaller result.
            _z = _z.pow(ONE.divDown(t));
        } else {
            // Rounding up the exponent results in a smaller result.
            _z = _z.pow(ONE.divUp(t));
        }
        // ((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        _z = _z.divDown(mu);

        // Δz = (((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ - ze
        return _z - ze;
    }

    /// @dev Calculates the amount of shares a user will receive from the pool
    ///      by providing a specified amount of bonds. This function reverts if
    ///      an integer overflow or underflow occurs. We underestimate the
    ///      amount of shares out.
    /// @param ze The effective share reserves.
    /// @param y The bond reserves.
    /// @param dy The amount of bonds paid to the pool.
    /// @param t The time elapsed since the term's start.
    /// @param c The vault share price.
    /// @param mu The initial vault share price.
    /// @return result The amount of shares the user receives.
    function calculateSharesOutGivenBondsInDown(
        uint256 ze,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 result) {
        bool success;
        (result, success) = calculateSharesOutGivenBondsInDownSafe(
            ze,
            y,
            dy,
            t,
            c,
            mu
        );
        if (!success) {
            revert IHyperdrive.InsufficientLiquidity(
                IHyperdrive.InsufficientLiquidityReason.ArithmeticUnderflow
            );
        }
    }

    /// @dev Calculates the amount of shares a user will receive from the pool
    ///      by providing a specified amount of bonds. This function returns a
    ///      success flag instead of reverting. We underestimate the amount of
    ///      shares out.
    /// @param ze The effective share reserves.
    /// @param y The bond reserves.
    /// @param dy The amount of bonds paid to the pool.
    /// @param t The time elapsed since the term's start.
    /// @param c The vault share price.
    /// @param mu The initial vault share price.
    /// @return result The amount of shares the user receives
    /// @return success A flag indicating if the calculation succeeded.
    function calculateSharesOutGivenBondsInDownSafe(
        uint256 ze,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 result, bool success) {
        // NOTE: We round k up to make the rhs of the equation larger.
        //
        // k = (c / µ) * (µ * ze)^(1 - t) + y^(1 - t)
        uint256 k = kUp(ze, y, t, c, mu);

        // (y + dy)^(1 - t)
        y = (y + dy).pow(t);

        // If k is less than y, we return with a failure flag.
        if (k < y) {
            return (0, false);
        }

        // NOTE: We round _z up to make the rhs of the equation larger.
        //
        // ((k - (y + dy)^(1 - t)) / (c / µ))^(1 / (1 - t)))
        uint256 _z = (k - y).mulDivUp(mu, c);
        if (_z >= ONE) {
            // Rounding the exponent up results in a larger outcome.
            _z = _z.pow(ONE.divUp(t));
        } else {
            // Rounding the exponent down results in a larger outcome.
            _z = _z.pow(ONE.divDown(t));
        }
        // ((k - (y + dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        _z = _z.divUp(mu);

        // Δz = ze - ((k - (y + dy)^(1 - t) ) / (c / µ))^(1 / (1 - t)) / µ
        if (ze > _z) {
            result = ze - _z;
        }
        success = true;
    }

    /// @dev Calculates the share payment required to purchase the maximum
    ///      amount of bonds from the pool.
    /// @param ze The effective share reserves.
    /// @param y The bond reserves.
    /// @param t The time elapsed since the term's start.
    /// @param c The vault share price.
    /// @param mu The initial vault share price.
    /// @return The share payment to purchase the maximum amount of bonds.
    function calculateMaxBuySharesIn(
        uint256 ze,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // We solve for the maximum buy using the constraint that the pool's
        // spot price can never exceed 1. We do this by noting that a spot price
        // of 1, ((mu * ze) / y) ** tau = 1, implies that mu * ze = y. This
        // simplifies YieldSpace to:
        //
        // k = ((c / mu) + 1) * (mu * ze') ** (1 - tau),
        //
        // This gives us the maximum effective share reserves of:
        //
        // ze' = (1 / mu) * (k / ((c / mu) + 1)) ** (1 / (1 - tau)).
        uint256 k = kDown(ze, y, t, c, mu);
        uint256 optimalZe = k.divDown(c.divUp(mu) + ONE);
        if (optimalZe >= ONE) {
            // Rounding the exponent down results in a smaller outcome.
            optimalZe = optimalZe.pow(ONE.divDown(t));
        } else {
            // Rounding the exponent up results in a smaller outcome.
            optimalZe = optimalZe.pow(ONE.divUp(t));
        }
        optimalZe = optimalZe.divDown(mu);

        // The optimal trade size is given by dz = ze' - ze.
        return optimalZe - ze;
    }

    /// @dev Calculates the maximum amount of bonds that can be purchased with
    ///      the specified reserves. We round so that the max buy amount is
    ///      underestimated.
    /// @param ze The effective share reserves.
    /// @param y The bond reserves.
    /// @param t The time elapsed since the term's start.
    /// @param c The vault share price.
    /// @param mu The initial vault share price.
    /// @return The maximum amount of bonds that can be purchased.
    function calculateMaxBuyBondsOut(
        uint256 ze,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // We can use the same derivation as in `calculateMaxBuySharesIn` to
        // calculate the minimum bond reserves as:
        //
        // y' = (k / ((c / mu) + 1)) ** (1 / (1 - tau)).
        uint256 k = kUp(ze, y, t, c, mu);
        uint256 optimalY = k.divUp(c.divDown(mu) + ONE);
        if (optimalY >= ONE) {
            // Rounding the exponent up results in a larger outcome.
            optimalY = optimalY.pow(ONE.divUp(t));
        } else {
            // Rounding the exponent down results in a larger outcome.
            optimalY = optimalY.pow(ONE.divDown(t));
        }

        // The optimal trade size is given by dy = y - y'.
        return y - optimalY;
    }

    /// @dev Calculates the maximum amount of bonds that can be sold with the
    ///      specified reserves. We round so that the max sell amount is
    ///      underestimated.
    /// @param z The share reserves.
    /// @param zeta The share adjustment.
    /// @param y The bond reserves.
    /// @param zMin The minimum share reserves.
    /// @param t The time elapsed since the term's start.
    /// @param c The vault share price.
    /// @param mu The initial vault share price.
    /// @return The maximum amount of bonds that can be sold.
    /// @return A flag indicating whether or not the calculation was successful.
    function calculateMaxSellBondsInSafe(
        uint256 z,
        int256 zeta,
        uint256 y,
        uint256 zMin,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256, bool) {
        // If the share adjustment is negative, the minimum share reserves is
        // given by `zMin - zeta`, which ensures that the share reserves never
        // fall below the minimum share reserves. Otherwise, the minimum share
        // reserves is just zMin.
        if (zeta < 0) {
            zMin = zMin + uint256(-zeta);
        }

        // We solve for the maximum bond amount using the constraint that the
        // pool's share reserves can never fall below the minimum share reserves
        // `zMin`. Substituting `ze = zMin` simplifies YieldSpace to:
        //
        // k = (c / mu) * (mu * zMin) ** (1 - tau) + y' ** (1 - tau)
        //
        // This gives us the maximum bonds that can be sold to the pool as:
        //
        // y' = (k - (c / mu) * (mu * zMin) ** (1 - tau)) ** (1 / (1 - tau)).
        uint256 ze = HyperdriveMath.calculateEffectiveShareReserves(z, zeta);
        uint256 k = kDown(ze, y, t, c, mu);
        uint256 optimalY = k - c.mulDivUp(mu.mulUp(zMin).pow(t), mu);
        if (optimalY >= ONE) {
            // Rounding the exponent down results in a smaller outcome.
            optimalY = optimalY.pow(ONE.divDown(t));
        } else {
            // Rounding the exponent up results in a smaller outcome.
            optimalY = optimalY.pow(ONE.divUp(t));
        }

        // The optimal trade size is given by dy = y' - y. If this subtraction
        // will underflow, we return a failure flag.
        if (optimalY < y) {
            return (0, false);
        }
        return (optimalY - y, true);
    }

    /// @dev Calculates the YieldSpace invariant k. This invariant is given by:
    ///
    ///      k = (c / µ) * (µ * ze)^(1 - t) + y^(1 - t)
    ///
    ///      This variant of the calculation overestimates the result.
    /// @param ze The effective share reserves.
    /// @param y The bond reserves.
    /// @param t The time elapsed since the term's start.
    /// @param c The vault share price.
    /// @param mu The initial vault share price.
    /// @return The YieldSpace invariant, k.
    function kUp(
        uint256 ze,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // NOTE: Rounding up to overestimate the result.
        //
        /// k = (c / µ) * (µ * ze)^(1 - t) + y^(1 - t)
        return c.mulDivUp(mu.mulUp(ze).pow(t), mu) + y.pow(t);
    }

    /// @dev Calculates the YieldSpace invariant k. This invariant is given by:
    ///
    ///      k = (c / µ) * (µ * ze)^(1 - t) + y^(1 - t)
    ///
    ///      This variant of the calculation underestimates the result.
    /// @param ze The effective share reserves.
    /// @param y The bond reserves.
    /// @param t The time elapsed since the term's start.
    /// @param c The vault share price.
    /// @param mu The initial vault share price.
    /// @return The modified YieldSpace Constant.
    function kDown(
        uint256 ze,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // NOTE: Rounding down to underestimate the result.
        //
        /// k = (c / µ) * (µ * ze)^(1 - t) + y^(1 - t)
        return c.mulDivDown(mu.mulDown(ze).pow(t), mu) + y.pow(t);
    }
}
