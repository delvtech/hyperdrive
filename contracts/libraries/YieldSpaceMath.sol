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
    /// @param _shareReserves yield bearing vault shares reserve amount, unit is shares
    /// @param _bondReserves bond reserves amount, unit is the face value in underlying
    /// @param _bondReserveAdjustment An optional adjustment to the reserve which MUST have units of underlying.
    /// @param _amountIn amount to be traded, if bonds in the unit is underlying, if shares in the unit is shares
    /// @param _stretchedTimeElapsed Amount of time elapsed since term start
    /// @param _c price of shares in terms of their base
    /// @param _mu Normalization factor -- starts as c at initialization
    /// @param _isBondOut determines if the output is bond or shares
    /// @return Amount of shares a user would get for given amount of bond
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
        uint256 cDivMu = _c.divDown(_mu);
        _bondReserves = _bondReserves.add(_bondReserveAdjustment);
        uint256 k = _k(
            cDivMu,
            _mu,
            _shareReserves,
            _stretchedTimeElapsed,
            _bondReserves
        );
        if (_isBondOut) {
            _shareReserves = _mu.mulDown(_shareReserves.add(_amountIn)).pow(
                _stretchedTimeElapsed
            );
            _shareReserves = cDivMu.mulDown(_shareReserves);
            uint256 rhs = k.sub(_shareReserves).pow(
                FixedPointMath.ONE_18.divDown(_stretchedTimeElapsed)
            );
            return _bondReserves.sub(rhs);
        } else {
            _bondReserves = _bondReserves.add(_amountIn).pow(
                _stretchedTimeElapsed
            );
            uint256 rhs = k.sub(_bondReserves).divDown(cDivMu).pow(
                FixedPointMath.ONE_18.divDown(_stretchedTimeElapsed)
            );
            rhs = rhs.divDown(_mu);
            return _shareReserves.sub(rhs);
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
    /// @return Amount of shares a user would get for given amount of bond
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
        uint256 cDivMu = _c.divDown(_mu);
        _bondReserves = _bondReserves.add(_bondReserveAdjustment);
        uint256 k = _k(
            cDivMu,
            _mu,
            _shareReserves,
            _stretchedTimeElapsed,
            _bondReserves
        );
        if (_isBondIn) {
            _shareReserves = _mu.mulDown(_shareReserves.sub(_amountOut)).pow(
                _stretchedTimeElapsed
            );
            _shareReserves = cDivMu.mulDown(_shareReserves);
            uint256 rhs = k.sub(_shareReserves).pow(
                FixedPointMath.ONE_18.divDown(_stretchedTimeElapsed)
            );
            return rhs.sub(_bondReserves);
        } else {
            _bondReserves = _bondReserves.sub(_amountOut).pow(
                _stretchedTimeElapsed
            );
            uint256 rhs = k.sub(_bondReserves).divDown(cDivMu).pow(
                FixedPointMath.ONE_18.divDown(_stretchedTimeElapsed)
            );
            rhs = rhs.divDown(_mu);
            return rhs.sub(_shareReserves);
        }
    }

    /// @dev Helper function
    ///
    /// (
    ///   c/mu
    ///   * (mu*shareReserves)^(1-t)
    ///   + bondReserves^(1-t)
    ///   - c/mu
    ///   * (mu*(shareReserves + amountIn))^(1-t) )^(1 / (1 - t)
    /// )
    /// returns k
    function _k(
        uint256 _cDivMu,
        uint256 _mu,
        uint256 _shareReserves,
        uint256 _stretchedTimeElapsed,
        uint256 _bondReserves
    ) private pure returns (uint256) {
        return
            _cDivMu
                .mulDown(_mu.mulDown(_shareReserves).pow(_stretchedTimeElapsed))
                .add(_bondReserves.pow(_stretchedTimeElapsed));
    }
}
