// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { LPMath } from "contracts/src/libraries/LPMath.sol";

contract MockLPMath {
    function calculateInitialBondReserves(
        uint256 _effectiveShareReserves,
        uint256 _initialVaultSharePrice,
        uint256 _apr,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) external pure returns (uint256) {
        uint256 result = LPMath.calculateInitialBondReserves(
            _effectiveShareReserves,
            _initialVaultSharePrice,
            _apr,
            _positionDuration,
            _timeStretch
        );
        return result;
    }

    function calculateUpdateLiquidity(
        uint256 _shareReserves,
        int256 _shareAdjustment,
        uint256 _bondReserves,
        uint256 _minimumShareReserves,
        int256 _shareReservesDelta,
        uint256 _spotPrice,
        uint256 _vaultSharePrice
    )
        external
        pure
        returns (
            uint256 shareReserves,
            int256 shareAdjustment,
            uint256 bondReserves
        )
    {
        bool success;
        (shareReserves, shareAdjustment, bondReserves, success) = LPMath
            .calculateUpdateLiquiditySafe(
                _shareReserves,
                _shareAdjustment,
                _bondReserves,
                _minimumShareReserves,
                _shareReservesDelta,
                _spotPrice,
                _vaultSharePrice
            );
        require(success, "MockLPMath: calculateUpdateLiquiditySafe failed");
    }

    function calculatePresentValue(
        LPMath.PresentValueParams memory _params
    ) external pure returns (uint256) {
        return LPMath.calculatePresentValue(_params);
    }

    function calculateNetFlatTrade(
        LPMath.PresentValueParams memory _params
    ) external pure returns (int256) {
        return LPMath.calculateNetFlatTrade(_params);
    }

    function calculateNetCurveTrade(
        LPMath.PresentValueParams memory _params
    ) external pure returns (int256) {
        (int256 netCurveTrade, bool success) = LPMath
            .calculateNetCurveTradeSafe(_params);
        require(success, "MockLPMath: calculateNetCurveTradeSafe failed");
        return netCurveTrade;
    }

    function calculateDistributeExcessIdleWithdrawalSharesRedeemed(
        LPMath.DistributeExcessIdleParams memory _params,
        uint256 _shareReservesDelta
    ) external pure returns (uint256) {
        return
            LPMath.calculateDistributeExcessIdleWithdrawalSharesRedeemed(
                _params,
                _shareReservesDelta
            );
    }

    function calculateDistributeExcessIdleShareProceeds(
        LPMath.DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves,
        uint256 _maxShareReservesDelta
    ) external pure returns (uint256) {
        return
            LPMath.calculateDistributeExcessIdleShareProceeds(
                _params,
                _originalEffectiveShareReserves,
                _maxShareReservesDelta,
                LPMath.SHARE_PROCEEDS_MAX_ITERATIONS
            );
    }

    function calculateMaxShareReservesDeltaSafe(
        LPMath.DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves
    ) external pure returns (uint256, bool) {
        return
            LPMath.calculateMaxShareReservesDeltaSafe(
                _params,
                _originalEffectiveShareReserves
            );
    }

    function calculateSharesDeltaGivenBondsDeltaDerivativeSafe(
        LPMath.DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves,
        int256 _bondAmount
    ) external pure returns (uint256, bool) {
        return
            LPMath.calculateSharesDeltaGivenBondsDeltaDerivativeSafe(
                _params,
                _originalEffectiveShareReserves,
                _bondAmount
            );
    }

    function calculateDistributeExcessIdleShareProceedsNetLongEdgeCaseSafe(
        LPMath.DistributeExcessIdleParams memory _params
    ) external pure returns (uint256, bool) {
        return
            LPMath
                .calculateDistributeExcessIdleShareProceedsNetLongEdgeCaseSafe(
                    _params
                );
    }
}
