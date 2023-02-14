/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";

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
    /// @param _shareReserves yield bearing vault shares reserve amount, unit is shares
    /// @param _bondReserves bond reserves amount, unit is the face value in underlying
    /// @param _bondReserveAdjustment An optional adjustment to the reserve which MUST have units of underlying.
    /// @param _amountIn amount to be traded, if bonds in the unit is underlying, if shares in the unit is shares
    /// @param _stretchedTimeElapsed Amount of time elapsed since term start
    /// @param _c price of shares in terms of their base
    /// @param _mu Normalization factor -- starts as c at initialization
    /// @param _isBondOut determines if the output is bond or shares
    /// @return Amount of shares/bonds
    function calculateOutGivenIn(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _bondReserveAdjustment,
        uint256 _amountIn,
        uint256 _stretchedTimeElapsed,
        uint256 _c,
        uint256 _mu,
        bool _isBondOut
    ) internal pure returns (uint256) {
        // c / mu
        uint256 cDivMu = _c.divDown(_mu);
        // Adjust the bond reserve, optionally shifts the curve around the
        // inflection point
        _bondReserves = _bondReserves.add(_bondReserveAdjustment);
        // (c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau)
        uint256 k = _k(
            cDivMu,
            _mu,
            _shareReserves,
            _stretchedTimeElapsed,
            _bondReserves
        );

        if (_isBondOut) {
            // (mu * (shareReserves + amountIn))^(1 - tau)
            _shareReserves = _mu.mulDown(_shareReserves.add(_amountIn)).pow(
                _stretchedTimeElapsed
            );
            // (c / mu) * (mu * (shareReserves + amountIn))^(1 - tau)
            _shareReserves = cDivMu.mulDown(_shareReserves);
            // NOTE: k - shareReserves >= 0 to avoid a complex number
            // ((c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (c / mu) * (mu * (shareReserves + amountIn))^(1 - tau))^(1 / (1 - tau)))
            uint256 newBondReserves = k.sub(_shareReserves).pow(
                FixedPointMath.ONE_18.divDown(_stretchedTimeElapsed)
            );
            // NOTE: bondReserves - newBondReserves >= 0, but I think avoiding a complex number in the step above ensures this never happens
            // bondsOut = bondReserves - ( (c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (c / mu) * (mu * (shareReserves + shareIn))^(1 - tau))^(1 / (1 - tau)))
            return _bondReserves.sub(newBondReserves);
        } else {
            // (bondReserves + amountIn)^(1 - tau)
            _bondReserves = _bondReserves.add(_amountIn).pow(
                _stretchedTimeElapsed
            );
            // NOTE: k - bondReserves >= 0 to avoid a complex number
            // (((mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves + amountIn)^(1 - tau)) / (c / mu))^(1 / (1 - tau)))
            uint256 newShareReserves = k.sub(_bondReserves).divDown(cDivMu).pow(
                FixedPointMath.ONE_18.divDown(_stretchedTimeElapsed)
            );
            // (((mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves + bondIn)^(1 - tau) ) / (c / mu))^(1 / (1 - tau))) / mu
            newShareReserves = newShareReserves.divDown(_mu);
            // NOTE: shareReserves - sharesOut >= 0, but I think avoiding a complex number in the step above ensures this never happens
            // sharesOut = shareReserves - (((c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves + bondIn)^(1 - tau) ) / (c / mu))^(1 / (1 - tau))) / mu
            return _shareReserves.sub(newShareReserves);
        }
    }

    /// @dev Calculates the amount of an asset that will be received given a
    ///      specified amount of the other asset given the current AMM reserves.
    /// @param _shareReserves yield bearing vault shares reserve amount, unit is shares
    /// @param _bondReserves bond reserves amount, unit is the face value in underlying
    /// @param _bondReserveAdjustment An optional adjustment to the reserve which MUST have units of underlying.
    /// @param _amountOut amount to be received, if bonds in the unit is underlying, if shares in the unit is shares
    /// @param _stretchedTimeElapsed Amount of time elapsed since term start
    /// @param _c price of shares in terms of their base
    /// @param _mu Normalization factor -- starts as c at initialization
    /// @param _isBondIn determines if the input is bond or shares
    /// @return Amount of shares/bonds
    function calculateInGivenOut(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _bondReserveAdjustment,
        uint256 _amountOut,
        uint256 _stretchedTimeElapsed,
        uint256 _c,
        uint256 _mu,
        bool _isBondIn
    ) internal pure returns (uint256) {
        // c / mu
        uint256 cDivMu = _c.divDown(_mu);
        // Adjust the bond reserve, optionally shifts the curve around the inflection point
        _bondReserves = _bondReserves.add(_bondReserveAdjustment);
        // (c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau)
        uint256 k = _k(
            cDivMu,
            _mu,
            _shareReserves,
            _stretchedTimeElapsed,
            _bondReserves
        );
        if (_isBondIn) {
            // (mu * (shareReserves - amountOut))^(1 - tau)
            _shareReserves = _mu.mulDown(_shareReserves.sub(_amountOut)).pow(
                _stretchedTimeElapsed
            );
            // (c / mu) * (mu * (shareReserves - amountOut))^(1 - tau)
            _shareReserves = cDivMu.mulDown(_shareReserves);
            // NOTE: k - shareReserves >= 0 to avoid a complex number
            // ((c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (c / mu) * (mu*(shareReserves - amountOut))^(1 - tau))^(1 / (1 - tau)))
            uint256 newBondReserves = k.sub(_shareReserves).pow(
                FixedPointMath.ONE_18.divDown(_stretchedTimeElapsed)
            );
            // NOTE: newBondReserves - bondReserves >= 0, but I think avoiding a complex number in the step above ensures this never happens
            // bondIn = ((c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (c / mu) * (mu * (shareReserves - shareOut))^(1 - tau))^(1 / (1 - tau))) - bondReserves
            return newBondReserves.sub(_bondReserves);
        } else {
            // (bondReserves - amountOut)^(1 - tau)
            _bondReserves = _bondReserves.sub(_amountOut).pow(
                _stretchedTimeElapsed
            );
            // NOTE: k - newScaledBondReserves >= 0 to avoid a complex number
            // (((mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves - amountOut)^(1 - tau) ) / (c / mu))^(1 / (1 - tau)))
            uint256 newShareReserves = k.sub(_bondReserves).divDown(cDivMu).pow(
                FixedPointMath.ONE_18.divDown(_stretchedTimeElapsed)
            );
            // (((mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves - amountOut)^(1 - tau) ) / (c / mu))^(1 / (1 - tau))) / mu
            newShareReserves = newShareReserves.divDown(_mu);
            // NOTE: newShareReserves - shareReserves >= 0, but I think avoiding a complex number in the step above ensures this never happens
            // sharesIn = (((c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves - bondOut)^(1 - tau) ) / (c / mu))^(1 / (1 - tau))) / mu - shareReserves
            return newShareReserves.sub(_shareReserves);
        }
    }

    /// @dev Helper function to derive invariant constant k
    /// @param _cDivMu Normalized price of shares in terms of base
    /// @param _mu Normalization factor -- starts as c at initialization
    /// @param _shareReserves Yield bearing vault shares reserve amount, unit is shares
    /// @param _stretchedTimeElapsed Amount of time elapsed since term start
    /// @param _bondReserves Bond reserves amount, unit is the face value in underlying
    /// returns k
    function _k(
        uint256 _cDivMu,
        uint256 _mu,
        uint256 _shareReserves,
        uint256 _stretchedTimeElapsed,
        uint256 _bondReserves
    ) private pure returns (uint256) {
        /// k = (c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau)
        return
            _cDivMu
                .mulDown(_mu.mulDown(_shareReserves).pow(_stretchedTimeElapsed))
                .add(_bondReserves.pow(_stretchedTimeElapsed));
    }
}
