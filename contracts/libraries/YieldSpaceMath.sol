/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

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

    struct YieldSpaceArgs {
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 bondReserveAdjustment;
        uint256 amount;
        uint256 t;
        uint256 s;
        uint256 c;
        uint256 mu;
    }

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
    ) internal pure returns (uint256) {
        YieldSpaceArgs memory args = YieldSpaceArgs({
            shareReserves: shareReserves,
            bondReserves: bondReserves,
            bondReserveAdjustment: bondReserveAdjustment,
            amount: amountIn,
            t: t,
            s: s,
            c: c,
            mu: mu
        });
        return
            isBondOut
                ? _calculateOutGivenInBondOut(args)
                : _calculateOutGivenInBondIn(args);
    }

    /// @dev Calculates the amount of an asset that will be received given a
    ///      specified amount of the other asset given the current AMM reserves.
    /// @param shareReserves yield bearing vault shares reserve amount, unit is shares
    /// @param bondReserves bond reserves amount, unit is the face value in underlying
    /// @param bondReserveAdjustment An optional adjustment to the reserve which MUST have units of underlying.
    /// @param amountOut amount to be received, if bonds in the unit is underlying, if shares in the unit is shares
    /// @param t time till maturity in seconds
    /// @param s time stretch coefficient.  e.g. 25 years in seconds
    /// @param c price of shares in terms of their base
    /// @param mu Normalization factor -- starts as c at initialization
    /// @param isBondIn determines if the input is bond or shares
    /// @return result the amount of shares a user would get for given amount of bond
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
    ) internal pure returns (uint256) {
        YieldSpaceArgs memory args = YieldSpaceArgs({
            shareReserves: shareReserves,
            bondReserves: bondReserves,
            bondReserveAdjustment: bondReserveAdjustment,
            amount: amountOut,
            t: t,
            s: s,
            c: c,
            mu: mu
        });
        return
            isBondIn
                ? _calculateInGivenOutBondIn(args)
                : _calculateInGivenOutBondOut(args);
    }

    function _calculateOutGivenInBondOut(
        YieldSpaceArgs memory _args
    ) private pure returns (uint256) {
        (
            uint256 oneMinusT,
            uint256 cDivMu,
            uint256 modifiedBondReserves,
            uint256 k
        ) = _internalYieldSpaceCalculations(_args);

        // bondOut = bondReserves - ( c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t) - c/mu * (mu*(shareReserves + shareIn))^(1-t) )^(1 / (1 - t))
        uint256 outReserves = modifiedBondReserves;

        // (mu*(shareReserves + amountIn))^(1-t)
        uint256 newScaledShareReserves = _args
            .mu
            .mulDown(_args.shareReserves.add(_args.amount))
            .pow(oneMinusT);
        // c/mu * (mu*(shareReserves + amountIn))^(1-t)
        newScaledShareReserves = cDivMu.mulDown(newScaledShareReserves);
        // Notes: k - newScaledShareReserves >= 0 to avoid a complex number
        // ( c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t) - c/mu * (mu*(shareReserves + amountIn))^(1-t) )^(1 / (1 - t))
        uint256 rhs = k.sub(newScaledShareReserves).pow(
            FixedPointMath.ONE_18.divDown(oneMinusT)
        );

        return outReserves.sub(rhs);
    }

    function _calculateOutGivenInBondIn(
        YieldSpaceArgs memory _args
    ) private pure returns (uint256) {
        (
            uint256 oneMinusT,
            uint256 cDivMu,
            uint256 modifiedBondReserves,
            uint256 k
        ) = _internalYieldSpaceCalculations(_args);

        uint256 outReserves = _args.shareReserves;
        // (bondReserves + bondIn)^(1-t)
        uint256 newScaledBondReserves = modifiedBondReserves
            .add(_args.amount)
            .pow(oneMinusT);
        // Notes: k - newScaledBondReserves >= 0 to avoid a complex number
        // [( (mu * shareReserves)^(1-t) + bondReserves^(1-t) - (bondReserves + bondIn)^(1-t) ) / c/u ]^(1 / (1 - t))
        uint256 rhs = k.sub(newScaledBondReserves).divDown(cDivMu).pow(
            FixedPointMath.ONE_18.divDown(oneMinusT)
        );
        // [( (mu * shareReserves)^(1-t) + bondReserves^(1-t) - (bondReserves + bondIn)^(1-t) ) / c/u ]^(1 / (1 - t)) / mu
        rhs = rhs.divDown(_args.mu);

        return outReserves.sub(rhs);
    }

    function _calculateInGivenOutBondIn(
        YieldSpaceArgs memory _args
    ) private pure returns (uint256) {
        (
            uint256 oneMinusT,
            uint256 cDivMu,
            uint256 modifiedBondReserves,
            uint256 k
        ) = _internalYieldSpaceCalculations(_args);

        // bondIn = ( c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t) - c/mu * (mu*(shareReserves - shareOut))^(1-t) )^(1 / (1 - t)) - bond_reserves
        uint256 inReserves = modifiedBondReserves;
        // (mu*(shareReserves - amountOut))^(1-t)
        uint256 newScaledShareReserves = _args
            .mu
            .mulDown(_args.shareReserves.sub(_args.amount))
            .pow(oneMinusT);
        // c/mu * (mu*(shareReserves - amountOut))^(1-t)
        newScaledShareReserves = cDivMu.mulDown(newScaledShareReserves);
        // Notes: k - newScaledShareReserves >= 0 to avoid a complex number
        // ( c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t) - c/mu * (mu*(shareReserves - amountOut))^(1-t) )^(1 / (1 - t))
        uint256 rhs = k.sub(newScaledShareReserves).pow(
            FixedPointMath.ONE_18.divDown(oneMinusT)
        );

        return rhs.sub(inReserves);
    }

    function _calculateInGivenOutBondOut(
        YieldSpaceArgs memory _args
    ) private pure returns (uint256) {
        (
            uint256 oneMinusT,
            uint256 cDivMu,
            uint256 modifiedBondReserves,
            uint256 k
        ) = _internalYieldSpaceCalculations(_args);

        // shareOut = [ ( c/mu * (mu * shareReserves)^(1-t) + bondReserves^(1-t) - (bondReserves - bondOut)^(1-t) ) / c/u  ]^(1 / (1 - t)) / mu - share_reserves
        uint256 inReserves = _args.shareReserves;
        // (bondReserves - amountOut)^(1-t)
        uint256 newScaledBondReserves = modifiedBondReserves
            .sub(_args.amount)
            .pow(oneMinusT);
        // Notes: k - newScaledBondReserves >= 0 to avoid a complex number
        // [( (mu * shareReserves)^(1-t) + bondReserves^(1-t) - (bondReserves - amountOut)^(1-t) ) / c/u ]^(1 / (1 - t))
        uint256 rhs = k.sub(newScaledBondReserves).divDown(cDivMu).pow(
            FixedPointMath.ONE_18.divDown(oneMinusT)
        );
        // [( (mu * shareReserves)^(1-t) + bondReserves^(1-t) - (bondReserves - amountOut)^(1-t) ) / c/u ]^(1 / (1 - t)) / mu
        rhs = rhs.divDown(_args.mu);

        return rhs.sub(inReserves);
    }

    function _internalYieldSpaceCalculations(
        YieldSpaceArgs memory _args
    )
        private
        pure
        returns (
            uint256 oneMinusT,
            uint256 cDivMu,
            uint256 modifiedBondReserves,
            uint256 k
        )
    {
        // Notes: 1 >= 1-st >= 0
        oneMinusT = FixedPointMath.ONE_18.sub(_args.s.mulDown(_args.t));
        // c/mu
        cDivMu = _args.c.divDown(_args.mu);
        // Adjust the bond reserve, optionally shifts the curve around the inflection point
        modifiedBondReserves = _args.bondReserves.add(
            _args.bondReserveAdjustment
        );
        // c/mu * (mu*shareReserves)^(1-t) + bondReserves^(1-t)
        k = cDivMu
            .mulDown(_args.mu.mulDown(_args.shareReserves).pow(oneMinusT))
            .add(modifiedBondReserves.pow(oneMinusT));
    }
}
