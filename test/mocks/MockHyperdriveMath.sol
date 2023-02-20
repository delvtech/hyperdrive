// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";

contract MockHyperdriveMath {
    function calculateAPRFromReserves(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _lpTotalSupply,
        uint256 _initialSharePrice,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateAPRFromReserves(
            _shareReserves,
            _bondReserves,
            _lpTotalSupply,
            _initialSharePrice,
            _positionDuration,
            _timeStretch
        );
        return result;
    }

    function calculateInitialBondReserves(
        uint256 _shareReserves,
        uint256 _sharePrice,
        uint256 _initialSharePrice,
        uint256 _apr,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateInitialBondReserves(
            _shareReserves,
            _sharePrice,
            _initialSharePrice,
            _apr,
            _positionDuration,
            _timeStretch
        );
        return result;
    }

    function calculateBondReserves(
        uint256 _shareReserves,
        uint256 _lpTotalSupply,
        uint256 _initialSharePrice,
        uint256 _apr,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateBondReserves(
            _shareReserves,
            _lpTotalSupply,
            _initialSharePrice,
            _apr,
            _positionDuration,
            _timeStretch
        );
        return result;
    }

    function calculateOpenLong(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _bondReserveAdjustment,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    ) external pure returns (uint256, uint256) {
        (uint256 result1, uint256 result2) = HyperdriveMath.calculateOpenLong(
            _shareReserves,
            _bondReserves,
            _bondReserveAdjustment,
            _amountIn,
            _normalizedTimeRemaining,
            _timeStretch,
            _sharePrice,
            _initialSharePrice
        );
        return (result1, result2);
    }

    function calculateCloseLong(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _bondReserveAdjustment,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    ) external pure returns (uint256, uint256) {
        (uint256 result1, uint256 result2) = HyperdriveMath.calculateCloseLong(
            _shareReserves,
            _bondReserves,
            _bondReserveAdjustment,
            _amountIn,
            _normalizedTimeRemaining,
            _timeStretch,
            _sharePrice,
            _initialSharePrice
        );
        return (result1, result2);
    }

    function calculateOpenShort(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _bondReserveAdjustment,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateOpenShort(
            _shareReserves,
            _bondReserves,
            _bondReserveAdjustment,
            _amountIn,
            _normalizedTimeRemaining,
            _timeStretch,
            _sharePrice,
            _initialSharePrice
        );
        return result;
    }

    function calculateCloseShort(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _bondReserveAdjustment,
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice,
        uint256 _curveFee,
        uint256 _flatFee
    ) external pure returns (uint256, uint256) {
        (uint256 result1, uint256 result2) = HyperdriveMath.calculateCloseShort(
            _shareReserves,
            _bondReserves,
            _bondReserveAdjustment,
            _amountOut,
            _normalizedTimeRemaining,
            _timeStretch,
            _sharePrice,
            _initialSharePrice,
            _curveFee,
            _flatFee
        );
        return (result1, result2);
    }

    function calculateSpotPrice(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _lpTotalSupply,
        uint256 _initialSharePrice,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateSpotPrice(
            _shareReserves,
            _bondReserves,
            _lpTotalSupply,
            _initialSharePrice,
            _normalizedTimeRemaining,
            _timeStretch
        );
        return result;
    }

    function calculateFeesOutGivenIn(
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice,
        uint256 _curveFeePercent,
        uint256 _flatFeePercent,
        bool _isBaseIn
    ) external pure returns (uint256, uint256) {
        (uint256 result1, uint256 result2) = HyperdriveMath
            .calculateFeesOutGivenIn(
                _amountIn,
                _normalizedTimeRemaining,
                _spotPrice,
                _sharePrice,
                _curveFeePercent,
                _flatFeePercent,
                _isBaseIn
            );
        return (result1, result2);
    }

    function calculateFeesInGivenOut(
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice,
        uint256 _curveFeePercent,
        uint256 _flatFeePercent,
        bool _isBaseOut
    ) external pure returns (uint256, uint256) {
        (uint256 result1, uint256 result2) = HyperdriveMath
            .calculateFeesInGivenOut(
                _amountOut,
                _normalizedTimeRemaining,
                _spotPrice,
                _sharePrice,
                _curveFeePercent,
                _flatFeePercent,
                _isBaseOut
            );
        return (result1, result2);
    }

    function calculateLpSharesOutForSharesIn(
        uint256 _shares,
        uint256 _shareReserves,
        uint256 _lpTotalSupply,
        uint256 _longsOutstanding,
        uint256 _shortsOutstanding,
        uint256 _sharePrice
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateLpSharesOutForSharesIn(
            _shares,
            _shareReserves,
            _lpTotalSupply,
            _longsOutstanding,
            _shortsOutstanding,
            _sharePrice
        );
        return result;
    }

    function calculateOutForLpSharesIn(
        uint256 _shares,
        uint256 _shareReserves,
        uint256 _lpTotalSupply,
        uint256 _longsOutstanding,
        uint256 _shortsOutstanding,
        uint256 _sharePrice
    ) external pure returns (uint256, uint256, uint256) {
        (uint256 result1, uint256 result2, uint256 result3) = HyperdriveMath
            .calculateOutForLpSharesIn(
                _shares,
                _shareReserves,
                _lpTotalSupply,
                _longsOutstanding,
                _shortsOutstanding,
                _sharePrice
            );
        return (result1, result2, result3);
    }
}
