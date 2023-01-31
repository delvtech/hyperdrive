/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { ElementError } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { YieldSpaceMath } from "contracts/libraries/YieldSpaceMath.sol";

// FIXME:
//
// The matrix of uses of flat+curve includes cases that should never occur.
// In particular, if isBondOut && t > 0 or isBondIn && t > 0, then the flat
// part refers to base tokens and the model doesn't make sense.
//
/// @notice Math for the Hyperdrive pricing model.
/// @author Element Finance
library HyperdriveMath {
    using FixedPointMath for uint256;

    /// @dev Calculates the amount of an asset that must be provided to receive
    ///      a specified amount of the other asset given the current AMM
    //       reserves.
    /// @dev Calculates the amount of an asset that will be received given a
    ///      specified amount of the other asset given the current AMM reserves.
    /// @param shareReserves The share reserves of the AMM.
    /// @param bondReserves The bonds reserves of the AMM.
    /// @param bondReserveAdjustment The bond reserves are adjusted to improve
    ///        the capital efficieny of the AMM. Otherwise, the APR would be 0%
    ///        when share_reserves = bond_reserves, which would ensure that half
    ///        of the pool reserves couldn't be used to provide liquidity.
    /// @param amountIn The amount of the asset that is provided.
    /// @param t The amount of time until maturity in seconds.
    /// @param s The time stretch parameter.
    /// @param c The share price.
    /// @param mu The initial share price.
    /// @param isBondOut A flag that specifies whether bonds are the asset being
    ///        received or the asset being provided.
    function calculateOutGivenIn(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 bondReserveAdjustment,
        uint256 amountIn,
        uint256 t,
        uint256 s,
        uint256 c,
        uint256 mu,
        bool isBondOut
    ) internal pure returns (
        uint256 poolBaseDelta,
        uint256 poolBondDelta,
        uint256 userDelta
    ) {
        // TODO: See if this is actually true.
        //
        // This pricing model only supports the purchasing of bonds when t = 1.
        if (isBondOut && t < 1) {
            revert ElementError.HyperdriveMath_BaseWithNonzeroTime();
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
                s,
                c,
                mu,
                isBondOut
            );
            return (
                amountIn,
                amountOut,
                amountOut,
            );
        } else {
            // Since we are trading bonds, it's possible that t < 1. We consider
            // (1-t)*amountIn of the bonds to be fully matured and t*amountIn of
            // the bonds to be newly minted. The fully matured bonds are redeemed
            // one-to-one (on the "flat" part of the curve) and the newly minted
            // bonds are traded on a YieldSpace curve configured to t = 1.
            uint256 flat = amountIn.mulDown(FixedPointMath.ONE_18.sub(t));
            uint256 curveIn = amountIn.mulDown(t);
            uint256 curveOut = YieldSpaceMath.calculateOutGivenIn(
                // Debit the share reserves by the flat trade.
                shareReserves.sub(flat.divDown(c)),
                // Credit the bond reserves by the flat trade.
                bondReserves.add(flat),
                bondReserveAdjustment,
                curveIn,
                FixedPointMath.ONE_18,
                s,
                c,
                mu,
                isBondOut
            );
            return (
                flat.add(curveOut),
                curveIn,
                flat.add(curveOut)
            );
        }
    }

    /// @dev Calculates the amount of an asset that will be received given a
    ///      specified amount of the other asset given the current AMM reserves.
    /// @param shareReserves The share reserves of the AMM.
    /// @param bondReserves The bonds reserves of the AMM.
    /// @param bondReserveAdjustment The bond reserves are adjusted to improve
    ///        the capital efficieny of the AMM. Otherwise, the APR would be 0%
    ///        when share_reserves = bond_reserves, which would ensure that half
    ///        of the pool reserves couldn't be used to provide liquidity.
    /// @param amountIn The amount of the asset that is provided.
    /// @param t The amount of time until maturity in seconds.
    /// @param s The time stretch parameter.
    /// @param c The share price.
    /// @param mu The initial share price.
    /// @param isBondOut A flag that specifies whether bonds are the asset being
    ///        received or the asset being provided.
    function calculateInGivenOut(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 bondReserveAdjustment,
        uint256 amountOut,
        uint256 t,
        uint256 s,
        uint256 c,
        uint256 mu,
        bool isBondIn
    ) internal pure returns (
        uint256 poolBaseDelta,
        uint256 poolBondDelta,
        uint256 userDelta
    ) {
        // TODO: See if this is actually true.
        //
        // This pricing model only supports the selling of bonds when t = 1.
        if (isBondIn && t < 1) {
            revert ElementError.HyperdriveMath_BaseWithNonzeroTime();
        }
        if (isBondIn) {
            // If bonds are being sold, then the entire trade occurs on the
            // curved portion since t = 1.
            uint256 amountIn = YieldSpaceMath.calculateInGivenOut(
                shareReserves,
                bondReserves,
                bondReserveAdjustment,
                amountIn,
                FixedPointMath.ONE_18,
                s,
                c,
                mu,
                isBondIn
            );
            return (
                amountOut,
                amountIn,
                amountIn,
            );
        } else {
            // Since we are trading bonds, it's possible that t < 1. We consider
            // (1-t)*amountIn of the bonds to be fully matured and t*amountIn of
            // the bonds to be newly minted. The fully matured bonds are redeemed
            // one-to-one (on the "flat" part of the curve) and the newly minted
            // bonds are traded on a YieldSpace curve configured to t = 1.
            uint256 flat = amountOut.mulDown(FixedPointMath.ONE_18.sub(t));
            uint256 curveOut = amountIn.mulDown(t);
            uint256 curveIn = YieldSpaceMath.calculateInGivenOut(
                // Credit the share reserves by the flat trade.
                shareReserves.add(flat.divDown(c)),
                // Debit the bond reserves by the flat trade.
                bondReserves.sub(flat),
                bondReserveAdjustment,
                curveOut,
                FixedPointMath.ONE_18,
                s,
                c,
                mu,
                isBondIn
            );
            return (
                flat.add(curveIn),
                curveIn,
                flat.add(curveIn)
            );
        }
    }
}
