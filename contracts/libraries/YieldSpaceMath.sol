/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "contracts/libraries/FixedPointMath.sol";

// FIXME: This doesn't compute the fee but maybe it should.
//
/// @author Delve
/// @title YieldSpaceMath
/// @notice Math for the YieldSpace pricing model.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library YieldSpaceMath {
    using FixedPointMath for uint256;

    /// Calculates the amount of bond a user would get for given amount of shares.
    /// @param shareReserves yield bearing vault shares reserve amount, unit is shares
    /// @param bondReserves bond reserves amount, unit is the face value in underlying
    /// @param bondReserveAdjustment An optional adjustment to the reserve which MUST have units of underlying.
    /// @param amountIn amount to be traded, if bonds in the unit is underlying, if shares in the unit is shares
    /// @param oneMinusT 1 - st
    /// @param c price of shares in terms of their base
    /// @param mu Normalization factor -- starts as c at initialization
    /// @param isBondOut determines if the output is bond or shares
    /// @return result the amount of shares a user would get for given amount of bond
    function calculateOutGivenIn(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 bondReserveAdjustment,
        uint256 amountIn,
        uint256 oneMinusT,
        uint256 c,
        uint256 mu,
        bool isBondOut
    ) internal pure returns (uint256) {
        uint256 cDivMu = c.divDown(mu);
        bondReserves = bondReserves.add(bondReserveAdjustment);
        uint256 k = _k(cDivMu, mu, shareReserves, oneMinusT, bondReserves);
        if (isBondOut) {
            shareReserves = mu.mulDown(shareReserves.add(amountIn)).pow(
                oneMinusT
            );
            shareReserves = cDivMu.mulDown(shareReserves);
            uint256 rhs = k.sub(shareReserves).pow(
                FixedPointMath.ONE_18.divDown(oneMinusT)
            );
            return bondReserves.sub(rhs);
        } else {
            bondReserves = bondReserves.add(amountIn).pow(oneMinusT);
            uint256 rhs = k.sub(bondReserves).divDown(cDivMu).pow(
                FixedPointMath.ONE_18.divDown(oneMinusT)
            );
            rhs = rhs.divDown(mu);
            return shareReserves.sub(rhs);
        }
    }

    /// @dev Calculates the amount of an asset that will be received given a
    ///      specified amount of the other asset given the current AMM reserves.
    /// @param shareReserves yield bearing vault shares reserve amount, unit is shares
    /// @param bondReserves bond reserves amount, unit is the face value in underlying
    /// @param bondReserveAdjustment An optional adjustment to the reserve which MUST have units of underlying.
    /// @param amountOut amount to be received, if bonds in the unit is underlying, if shares in the unit is shares
    /// @param oneMinusT 1 - st
    /// @param c price of shares in terms of their base
    /// @param mu Normalization factor -- starts as c at initialization
    /// @param isBondIn determines if the input is bond or shares
    /// @return result the amount of shares a user would get for given amount of bond
    function calculateInGivenOut(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 bondReserveAdjustment,
        uint256 amountOut,
        uint256 oneMinusT,
        uint256 c,
        uint256 mu,
        bool isBondIn
    ) internal pure returns (uint256) {
        uint256 cDivMu = c.divDown(mu);
        bondReserves = bondReserves.add(bondReserveAdjustment);
        uint256 k = _k(cDivMu, mu, shareReserves, oneMinusT, bondReserves);
        if (isBondIn) {
            shareReserves = mu.mulDown(shareReserves.sub(amountOut)).pow(
                oneMinusT
            );
            shareReserves = cDivMu.mulDown(shareReserves);
            uint256 rhs = k.sub(shareReserves).pow(
                FixedPointMath.ONE_18.divDown(oneMinusT)
            );
            return rhs.sub(bondReserves);
        } else {
            bondReserves = bondReserves.sub(amountOut).pow(oneMinusT);
            uint256 rhs = k.sub(bondReserves).divDown(cDivMu).pow(
                FixedPointMath.ONE_18.divDown(oneMinusT)
            );
            rhs = rhs.divDown(mu);
            return rhs.sub(shareReserves);
        }
    }

    function _k(
        uint256 cDivMu,
        uint256 mu,
        uint256 shareReserves,
        uint256 oneMinusT,
        uint256 modifiedBondReserves
    ) private pure returns (uint256) {
        return
            cDivMu.mulDown(mu.mulDown(shareReserves).pow(oneMinusT)).add(
                modifiedBondReserves.pow(oneMinusT)
            );
    }
}
