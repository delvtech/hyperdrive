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
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dz Amount of shares user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return The amount of bonds the user will receive
    function calculateBondsOutGivenSharesInDown(
        uint256 z,
        uint256 y,
        uint256 dz,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // NOTE: We round k up to make the rhs of the equation larger.
        //
        // k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        uint256 k = kUp(z, y, t, c, mu);

        // NOTE: We round z down to make the rhs of the equation larger.
        //
        // (µ * (z + dz))^(1 - t)
        z = mu.mulDown(z + dz).pow(t);
        // (c / µ) * (µ * (z + dz))^(1 - t)
        z = c.mulDivDown(z, mu);

        // NOTE: We round _y up to make the rhs of the equation larger.
        //
        // k - (c / µ) * (µ * (z + dz))^(1 - t))^(1 / (1 - t)))
        uint256 _y = k - z;
        if (_y >= ONE) {
            // Rounding up the exponent results in a larger result.
            _y = _y.pow(ONE.divUp(t));
        } else {
            // Rounding down the exponent results in a larger result.
            _y = _y.pow(ONE.divDown(t));
        }

        // Δy = y - (k - (c / µ) * (µ * (z + dz))^(1 - t))^(1 / (1 - t)))
        return y - _y;
    }

    /// @dev Calculates the amount of shares a user must provide the pool to
    ///      receive a specified amount of bonds. We overestimate the amount of
    ///      shares in.
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dy Amount of bonds user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return The amount of shares the user will pay
    function calculateSharesInGivenBondsOutUp(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // NOTE: We round k up to make the lhs of the equation larger.
        //
        // k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        uint256 k = kUp(z, y, t, c, mu);

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

        // Δz = (((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ - z
        return _z - z;
    }

    /// @dev Calculates the amount of shares a user must provide the pool to
    ///      receive a specified amount of bonds. We underestimate the amount of
    ///      shares in.
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dy Amount of bonds user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return The amount of shares the user will pay
    function calculateSharesInGivenBondsOutDown(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // NOTE: We round k down to make the lhs of the equation smaller.
        //
        // k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        uint256 k = kDown(z, y, t, c, mu);

        // (y - dy)^(1 - t)
        y = (y - dy).pow(t);

        // NOTE: We round _z down to make the lhs of the equation smaller.
        //
        // ((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))
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

        // Δz = (((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ - z
        return _z - z;
    }

    /// @dev Calculates the amount of shares a user will receive from the pool
    ///      by providing a specified amount of bonds. This function reverts if
    ///      an integer overflow or underflow occurs. We underestimate the
    ///      amount of shares out.
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dy Amount of bonds user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return result The amount of shares the user will receive
    function calculateSharesOutGivenBondsInDown(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 result) {
        bool success;
        (result, success) = calculateSharesOutGivenBondsInDownSafe(
            z,
            y,
            dy,
            t,
            c,
            mu
        );
        if (!success) {
            revert IHyperdrive.InvalidTradeSize();
        }
    }

    /// @dev Calculates the amount of shares a user will receive from the pool
    ///      by providing a specified amount of bonds. This function returns a
    ///      success flag instead of reverting. We underestimate the amount of
    ///      shares out.
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dy Amount of bonds user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return result The amount of shares the user will receive
    /// @return success A flag indicating whether or not the calculation succeeded.
    function calculateSharesOutGivenBondsInDownSafe(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 result, bool success) {
        // NOTE: We round k up to make the rhs of the equation larger.
        //
        // k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        uint256 k = kUp(z, y, t, c, mu);

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

        // Δz = z - ((k - (y + dy)^(1 - t) ) / (c / µ))^(1 / (1 - t)) / µ
        if (z > _z) {
            result = z - _z;
        }
        success = true;
    }

    /// @dev Calculates the maximum amount of bonds that can be purchased with
    ///      the specified reserves. We round so that the max buy amount is
    ///      underestimated.
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return The maximum amount of bonds that can be purchased.
    function calculateMaxBuy(
        uint256 z,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // We solve for the maximum buy using the constraint that the pool's
        // spot price can never exceed 1. We do this by noting that a spot price
        // of 1, (mu * z) / y ** tau = 1, implies that mu * z = y. This
        // simplifies YieldSpace to k = ((c / mu) + 1) * y' ** (1 - tau), and
        // gives us the maximum bond reserves of
        // y' = (k / ((c / mu) + 1)) ** (1 / (1 - tau)) and the maximum share
        // reserves of z' = y/mu.
        uint256 k = kUp(z, y, t, c, mu);
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
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param zMin The minimum share reserves.
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return The maximum amount of bonds that can be sold.
    function calculateMaxSell(
        uint256 z,
        uint256 y,
        uint256 zMin,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // We solve for the maximum sell using the constraint that the pool's
        // share reserves can never fall below the minimum share reserves zMin.
        // Substituting z = zMin simplifies YieldSpace to
        // k = (c / mu) * (mu * (zMin)) ** (1 - tau) + y' ** (1 - tau), and
        // gives us the maximum bond reserves of
        // y' = (k - (c / mu) * (mu * (zMin)) ** (1 - tau)) ** (1 / (1 - tau)).
        uint256 k = kDown(z, y, t, c, mu);
        uint256 optimalY = k - c.mulDivUp(mu.mulUp(zMin).pow(t), mu);
        if (optimalY >= ONE) {
            // Rounding the exponent down results in a smaller outcome.
            optimalY = optimalY.pow(ONE.divDown(t));
        } else {
            // Rounding the exponent up results in a smaller outcome.
            optimalY = optimalY.pow(ONE.divUp(t));
        }

        // The optimal trade size is given by dy = y' - y.
        return optimalY - y;
    }

    /// @dev Helper function to derive the invariant constant k. This variant
    ///      overestimates the result.
    /// @param z Amount of share reserves in the pool.
    /// @param y Amount of bond reserves in the pool.
    /// @param t Amount of time elapsed since term start.
    /// @param c Conversion rate between base and shares.
    /// @param mu Interest normalization factor for shares.
    /// @return The modified YieldSpace Constant.
    function kUp(
        uint256 z,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        /// k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        return c.mulDivUp(mu.mulUp(z).pow(t), mu) + y.pow(t);
    }

    /// @dev Helper function to derive the invariant constant k. This variant
    ///      underestimates the result.
    /// @param z Amount of share reserves in the pool.
    /// @param y Amount of bond reserves in the pool.
    /// @param t Amount of time elapsed since term start.
    /// @param c Conversion rate between base and shares.
    /// @param mu Interest normalization factor for shares.
    /// @return The modified YieldSpace Constant.
    function kDown(
        uint256 z,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        /// k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        return c.mulDivDown(mu.mulDown(z).pow(t), mu) + y.pow(t);
    }
}
