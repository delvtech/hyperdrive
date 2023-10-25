/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { FixedPointMath } from "./FixedPointMath.sol";
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

    // FIXME: Account for the exponent when over or underestimating.
    //
    /// @dev Calculates the amount of bonds a user will receive from the pool by
    ///      providing a specified amount of shares. We underestimate the amount
    ///      of bonds out to prevent sandwiches.
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dz Amount of shares user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return The amount of bonds the user will receive
    function calculateBondsOutGivenSharesIn(
        uint256 z,
        uint256 y,
        uint256 dz,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        uint256 k = modifiedYieldSpaceConstant(c.divDown(mu), mu, z, t, y);
        // (µ * (z + dz))^(1 - t)
        z = mu.mulUp(z + dz).pow(t);
        // (c / µ) * (µ * (z + dz))^(1 - t)
        z = c.mulDivUp(z, mu);
        // ((c / µ) * (µ * z)^(1 - t) + y^(1 - t) - (c / µ) * (µ * (z + dz))^(1 - t))^(1 / (1 - t)))
        uint256 _y = (k - z).pow(FixedPointMath.ONE_18.divUp(t));
        // Δy = y - ((c / µ) * (µ * z)^(1 - t) + y^(1 - t) - (c / µ) * (µ * (z + dz))^(1 - t))^(1 / (1 - t)))
        return y - _y;
    }

    // FIXME: Account for the exponent when over or underestimating.
    //
    /// @dev Calculates the amount of shares a user must provide the pool to
    ///      receive a specified amount of bonds. We overestimate the shares the
    ///      trader will need to provide to prevent sandwiches.
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dy Amount of bonds user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return The amount of shares the user will pay
    function calculateSharesInGivenBondsOut(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        uint256 k = modifiedYieldSpaceConstant(c.divUp(mu), mu, z, t, y);
        // (y - dy)^(1 - t)
        y = (y - dy).pow(t);
        // (((µ * z)^(1 - t) + y^(1 - t) - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))
        uint256 _z = (k - y).mulDivUp(mu, c).pow(
            FixedPointMath.ONE_18.divUp(t)
        );
        // (((µ * z)^(1 - t) + y^(1 - t) - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        _z = _z.divUp(mu);
        // Δz = ((((c / µ) * (µ * z)^(1 - t) + y^(1 - t) - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ) - z
        return _z - z;
    }

    // FIXME: Account for the exponent when over or underestimating.
    //
    /// @dev Calculates the amount of shares a user will receive from the pool
    ///      by providing a specified amount of bonds. This function reverts if
    ///      an integer overflow or underflow occurs. We overestimate the amount
    ///      of shares out which prevents sandwiches in the case of opening a
    ///      short.
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dy Amount of bonds user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return result The amount of shares the user will receive
    function calculateSharesOutGivenBondsOverestimateIn(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 result) {
        bool success;
        (result, success) = calculateSharesOutGivenBondsInOverestimateSafe(
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

    // FIXME: Account for the exponent when over or underestimating.
    //
    /// @dev Calculates the amount of shares a user will receive from the pool
    ///      by providing a specified amount of bonds. This function returns a
    ///      success flag instead of reverting. We overestimate the amount of
    ///      shares out which prevents sandwiches in the case of opening a short.
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dy Amount of bonds user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return result The amount of shares the user will receive
    /// @return success A flag indicating whether or not the calculation succeeded.
    function calculateSharesOutGivenBondsInOverestimateSafe(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 result, bool success) {
        // (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        uint256 k = modifiedYieldSpaceConstant(c.divDown(mu), mu, z, t, y);
        // (y + dy)^(1 - t)
        y = (y + dy).pow(t);
        if (k < y) {
            return (0, false);
        }
        // (((µ * z)^(1 - t) + y^(1 - t) - (y + dy)^(1 - t)) / (c / µ))^(1 / (1 - t)))
        uint256 _z = (k - y).mulDivDown(mu, c).pow(
            FixedPointMath.ONE_18.divUp(t)
        );
        // (((µ * z)^(1 - t) + y^(1 - t) - (y + dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        _z = _z.divDown(mu);
        // Δz = z - (((c / µ) * (µ * z)^(1 - t) + y^(1 - t) - (y + dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        if (z > _z) {
            result = z - _z;
        }
        success = true;
    }

    // FIXME: Account for the exponent when over or underestimating.
    //
    /// @dev Calculates the amount of shares a user will receive from the pool
    ///      by providing a specified amount of bonds. This function reverts if
    ///      an integer overflow or underflow occurs. We underestimate the
    ///      amount of shares out which prevents sandwiches in the case of
    ///      closing a long.
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dy Amount of bonds user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return result The amount of shares the user will receive
    function calculateSharesOutGivenBondsUnderestimateIn(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 result) {
        bool success;
        (result, success) = calculateSharesOutGivenBondsInUnderestimateSafe(
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

    // FIXME: Account for the exponent when over or underestimating.
    //
    /// @dev Calculates the amount of shares a user will receive from the pool
    ///      by providing a specified amount of bonds. This function returns a
    ///      success flag instead of reverting. We overestimate the amount of
    ///      shares out which prevents sandwiches in the case of opening a short
    ///      because it implies a higher fixed rate.
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dy Amount of bonds user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return result The amount of shares the user will receive
    /// @return success A flag indicating whether or not the calculation succeeded.
    function calculateSharesOutGivenBondsInUnderestimateSafe(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 result, bool success) {
        // (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        uint256 k = modifiedYieldSpaceConstant(c.divUp(mu), mu, z, t, y);
        // (y + dy)^(1 - t)
        y = (y + dy).pow(t);
        if (k < y) {
            return (0, false);
        }
        // (((µ * z)^(1 - t) + y^(1 - t) - (y + dy)^(1 - t)) / (c / µ))^(1 / (1 - t)))
        uint256 _z = (k - y).mulDivUp(mu, c).pow(
            FixedPointMath.ONE_18.divUp(t)
        );
        // (((µ * z)^(1 - t) + y^(1 - t) - (y + dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        _z = _z.divUp(mu);
        // Δz = z - (((c / µ) * (µ * z)^(1 - t) + y^(1 - t) - (y + dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        if (z > _z) {
            result = z - _z;
        }
        success = true;
    }

    /// @dev Calculates the maximum amount of bonds that can be purchased with
    ///      the specified reserves.
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return The cost in shares of the maximum bond purchase.
    /// @return The maximum amount of bonds that can be purchased.
    function calculateMaxBuy(
        uint256 z,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256, uint256) {
        // We solve for the maximum buy using the constraint that the pool's
        // spot price can never exceed 1. We do this by noting that a spot price
        // of 1, (mu * z) / y ** tau = 1, implies that mu * z = y. This
        // simplifies YieldSpace to k = ((c / mu) + 1) * y' ** (1 - tau), and
        // gives us the maximum bond reserves of y' = (k / ((c / mu) + 1)) ** (1 / (1 - tau))
        // and the maximum share reserves of z' = y/mu.
        uint256 cDivMu = c.divDown(mu);
        uint256 k = modifiedYieldSpaceConstant(cDivMu, mu, z, t, y);
        uint256 optimalY = (k.divDown(cDivMu + FixedPointMath.ONE_18)).pow(
            FixedPointMath.ONE_18.divDown(t)
        );
        uint256 optimalZ = optimalY.divDown(mu);

        // The optimal trade sizes are given by dz = z' - z and dy = y - y'.
        return (optimalZ - z, y - optimalY);
    }

    /// @dev Calculates the maximum amount of bonds that can be sold with the
    ///      specified reserves.
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param zMin The minimum share reserves.
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    /// @return The proceeds in shares of the maximum bond sale.
    /// @return The maximum amount of bonds that can be sold.
    function calculateMaxSell(
        uint256 z,
        uint256 y,
        uint256 zMin,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256, uint256) {
        // We solve for the maximum sell using the constraint that the pool's
        // share reserves can never fall below the minimum share reserves zMin.
        // Substituting z = zMin simplifies YieldSpace to
        // k = (c / mu) * (mu * (zMin)) ** (1 - tau) + y' ** (1 - tau), and gives
        // us the maximum bond reserves of
        // y' = (k - (c / mu) * (mu * (zMin)) ** (1 - tau)) ** (1 / (1 - tau)).
        uint256 cDivMu = c.divDown(mu);
        uint256 k = modifiedYieldSpaceConstant(cDivMu, mu, z, t, y);
        uint256 optimalY = (k - cDivMu.mulDown(mu.mulDown(zMin).pow(t))).pow(
            FixedPointMath.ONE_18.divDown(t)
        );

        // The optimal trade sizes are given by dz = z - zMin and dy = y' - y.
        return (z - zMin, optimalY - y);
    }

    // FIXME: Rename this to k.
    //
    /// @dev Helper function to derive invariant constant C
    /// @param cDivMu Normalized price of shares in terms of base
    /// @param mu Interest normalization factor for shares
    /// returns C The modified YieldSpace Constant
    /// @param z Amount of share reserves in the pool
    /// @param t Amount of time elapsed since term start
    /// @param y Amount of bond reserves in the pool
    function modifiedYieldSpaceConstant(
        uint256 cDivMu,
        uint256 mu,
        uint256 z,
        uint256 t,
        uint256 y
    ) internal pure returns (uint256) {
        /// k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        return cDivMu.mulDown(mu.mulDown(z).pow(t)) + y.pow(t);
    }
}
