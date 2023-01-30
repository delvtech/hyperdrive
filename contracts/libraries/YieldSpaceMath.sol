/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "contracts/libraries/FixedPointMath.sol";

/// @notice YieldSpace math library.
/// @author Element Finance
library YieldSpaceMath {
    using FixedPointMath for uint256;

    /// Calculates the amount of bond a user would get for given amount of shares.
    /// @param shareReserves yield bearing vault shares reserve amount, unit is shares
    /// @param bondReserves bond reserves amount, unit is the face value in underlying
    /// @param bondReserveAdjustment An optional adjustment to the reserve which MUST have units of underlying.
    /// @param amountIn amount to be traded, if bonds in the unit is underlying, if shares in the unit is shares
    /// @param t time till maturity in seconds
    /// @param s time stretch coefficient.  e.g. 25 years in seconds
    /// @param c price of shares in terms of their base
    /// @param mu Normalization factor -- starts as c at initialization
    /// @param isBondOut determines if the output is bond or shares
    /// @return result the amount of shares a user would get for given amount of bond
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
    ) internal pure returns (uint256 result) {
        uint256 outReserves;
        uint256 rhs;
        // Notes: 1 >= 1-st >= 0
        uint256 oneMinusT = FixedPointMath.ONE_18.sub(s.mulDown(t));
        // c/mu
        uint256 cDivMu = c.divDown(mu);
        // Adjust the bond reserve, optionally shifts the curve around the inflection point
        uint256 modifiedBondReserves = bondReserves.add(bondReserveAdjustment);
        // c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t)
        uint256 k = cDivMu
            .mulDown(mu.mulDown(shareReserves).pow(oneMinusT))
            .add(modifiedBondReserves.pow(oneMinusT));

        if (isBondOut) {
            // bondOut = bondReserves - ( c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t) - c/mu * (mu*(shareReserves + shareIn))^(1-t) )^(1 / (1 - t))
            outReserves = modifiedBondReserves;
            // (mu*(shareReserves + amountIn))^(1-t)
            uint256 newScaledShareReserves = mu
                .mulDown(shareReserves.add(amountIn))
                .pow(oneMinusT);
            // c/mu * (mu*(shareReserves + amountIn))^(1-t)
            newScaledShareReserves = cDivMu.mulDown(newScaledShareReserves);
            // Notes: k - newScaledShareReserves >= 0 to avoid a complex number
            // ( c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t) - c/mu * (mu*(shareReserves + amountIn))^(1-t) )^(1 / (1 - t))
            rhs = k.sub(newScaledShareReserves).pow(
                FixedPointMath.ONE_18.divDown(oneMinusT)
            );
        } else {
            // shareOut = shareReserves - [ ( c/mu * (mu * shareReserves)^(1-t) + bondReserves^(1-t) - (bondReserves + bondIn)^(1-t) ) / c/u  ]^(1 / (1 - t)) / mu
            outReserves = shareReserves;
            // (bondReserves + bondIn)^(1-t)
            uint256 newScaledBondReserves = modifiedBondReserves
                .add(amountIn)
                .pow(oneMinusT);
            // Notes: k - newScaledBondReserves >= 0 to avoid a complex number
            // [( (mu * shareReserves)^(1-t) + bondReserves^(1-t) - (bondReserves + bondIn)^(1-t) ) / c/u ]^(1 / (1 - t))
            rhs = k.sub(newScaledBondReserves).divDown(cDivMu).pow(
                FixedPointMath.ONE_18.divDown(oneMinusT)
            );
            // [( (mu * shareReserves)^(1-t) + bondReserves^(1-t) - (bondReserves + bondIn)^(1-t) ) / c/u ]^(1 / (1 - t)) / mu
            rhs = rhs.divDown(mu);
        }
        // Notes: outReserves - rhs >= 0, but i think avoiding a complex number in the step above ensures this never happens
        result = outReserves.sub(rhs);
    }
}
