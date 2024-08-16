// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { HyperdriveMath } from "../src/libraries/HyperdriveMath.sol";
import { HyperdriveUtils } from "../../test/utils/HyperdriveUtils.sol";

contract MockHyperdriveMath {
    function calculateSpotAPR(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _initialVaultSharePrice,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateSpotAPR(
            _effectiveShareReserves,
            _bondReserves,
            _initialVaultSharePrice,
            _positionDuration,
            _timeStretch
        );
        return result;
    }

    function calculateEffectiveShareReserves(
        uint256 _shareReserves,
        int256 _shareAdjustment
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateEffectiveShareReserves(
            _shareReserves,
            _shareAdjustment
        );
        return result;
    }

    function calculateOpenLong(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _timeStretch,
        uint256 _vaultSharePrice,
        uint256 _initialVaultSharePrice
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateOpenLong(
            _effectiveShareReserves,
            _bondReserves,
            _amountIn,
            _timeStretch,
            _vaultSharePrice,
            _initialVaultSharePrice
        );
        return result;
    }

    function calculateCloseLong(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _vaultSharePrice,
        uint256 _initialVaultSharePrice
    ) external pure returns (uint256, uint256, uint256) {
        (uint256 result1, uint256 result2, uint256 result3) = HyperdriveMath
            .calculateCloseLong(
                _effectiveShareReserves,
                _bondReserves,
                _amountIn,
                _normalizedTimeRemaining,
                _timeStretch,
                _vaultSharePrice,
                _initialVaultSharePrice
            );
        return (result1, result2, result3);
    }

    function calculateOpenShort(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _timeStretch,
        uint256 _vaultSharePrice,
        uint256 _initialVaultSharePrice
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateOpenShort(
            _effectiveShareReserves,
            _bondReserves,
            _amountIn,
            _timeStretch,
            _vaultSharePrice,
            _initialVaultSharePrice
        );
        return result;
    }

    function calculateCloseShort(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _vaultSharePrice,
        uint256 _initialVaultSharePrice
    ) external pure returns (uint256, uint256, uint256) {
        (uint256 result1, uint256 result2, uint256 result3) = HyperdriveMath
            .calculateCloseShort(
                _effectiveShareReserves,
                _bondReserves,
                _amountOut,
                _normalizedTimeRemaining,
                _timeStretch,
                _vaultSharePrice,
                _initialVaultSharePrice
            );
        return (result1, result2, result3);
    }

    struct NegativeInterestOnCloseOutput {
        uint256 shareProceeds;
        uint256 shareReservesDelta;
        uint256 shareCurveDelta;
        int256 shareAdjustmentDelta;
        uint256 totalGovernanceFee;
    }

    function calculateNegativeInterestOnClose(
        uint256 _shareProceeds,
        uint256 _shareReservesDelta,
        uint256 _shareCurveDelta,
        uint256 _totalGovernanceFee,
        uint256 _openVaultSharePrice,
        uint256 _closeVaultSharePrice,
        bool _isLong
    ) external pure returns (uint256, uint256, uint256, int256, uint256) {
        NegativeInterestOnCloseOutput memory output;
        (
            output.shareProceeds,
            output.shareReservesDelta,
            output.shareCurveDelta,
            output.shareAdjustmentDelta,
            output.totalGovernanceFee
        ) = HyperdriveMath.calculateNegativeInterestOnClose(
            _shareProceeds,
            _shareReservesDelta,
            _shareCurveDelta,
            _totalGovernanceFee,
            _openVaultSharePrice,
            _closeVaultSharePrice,
            _isLong
        );
        return (
            output.shareProceeds,
            output.shareReservesDelta,
            output.shareCurveDelta,
            output.shareAdjustmentDelta,
            output.totalGovernanceFee
        );
    }

    function calculateTimeStretch(
        uint256 apr,
        uint256 positionDuration
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateTimeStretch(
            apr,
            positionDuration
        );
        return result;
    }

    function calculateMaxLong(
        HyperdriveUtils.MaxTradeParams memory _params,
        int256 _checkpointExposure,
        uint256 _maxIterations
    ) external pure returns (uint256, uint256) {
        (uint256 result1, uint256 result2) = HyperdriveUtils.calculateMaxLong(
            _params,
            _checkpointExposure,
            _maxIterations
        );
        return (result1, result2);
    }

    function calculateAbsoluteMaxLong(
        HyperdriveUtils.MaxTradeParams memory _params,
        uint256 _effectiveShareReserves,
        uint256 _spotPrice
    ) external pure returns (uint256, uint256) {
        (uint256 result1, uint256 result2) = HyperdriveUtils
            .calculateAbsoluteMaxLong(
                _params,
                _effectiveShareReserves,
                _spotPrice
            );
        return (result1, result2);
    }

    function calculateMaxShort(
        HyperdriveUtils.MaxTradeParams memory _params,
        int256 _checkpointExposure,
        uint256 _maxIterations
    ) external pure returns (uint256) {
        return
            HyperdriveUtils.calculateMaxShort(
                _params,
                _checkpointExposure,
                _maxIterations
            );
    }

    function calculateSpotPrice(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _initialVaultSharePrice,
        uint256 _timeStretch
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateSpotPrice(
            _shareReserves,
            _bondReserves,
            _initialVaultSharePrice,
            _timeStretch
        );
        return result;
    }

    function calculateShortProceedsUp(
        uint256 _bondAmount,
        uint256 _shareAmount,
        uint256 _openVaultSharePrice,
        uint256 _closeVaultSharePrice,
        uint256 _vaultSharePrice,
        uint256 _flatFee
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateShortProceedsUp(
            _bondAmount,
            _shareAmount,
            _openVaultSharePrice,
            _closeVaultSharePrice,
            _vaultSharePrice,
            _flatFee
        );
        return result;
    }

    function calculateShortProceedsDown(
        uint256 _bondAmount,
        uint256 _shareAmount,
        uint256 _openVaultSharePrice,
        uint256 _closeVaultSharePrice,
        uint256 _vaultSharePrice,
        uint256 _flatFee
    ) external pure returns (uint256) {
        uint256 result = HyperdriveMath.calculateShortProceedsDown(
            _bondAmount,
            _shareAmount,
            _openVaultSharePrice,
            _closeVaultSharePrice,
            _vaultSharePrice,
            _flatFee
        );
        return result;
    }
}
