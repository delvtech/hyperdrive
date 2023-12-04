// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { LPMath } from "contracts/src/libraries/LPMath.sol";

contract MockLPMath {
    function calculateUpdateLiquidity(
        uint256 _shareReserves,
        int256 _shareAdjustment,
        uint256 _bondReserves,
        uint256 _minimumShareReserves,
        int256 _shareReservesDelta
    )
        external
        pure
        returns (
            uint256 shareReserves,
            int256 shareAdjustment,
            uint256 bondReserves
        )
    {
        return
            LPMath.calculateUpdateLiquidity(
                _shareReserves,
                _shareAdjustment,
                _bondReserves,
                _minimumShareReserves,
                _shareReservesDelta
            );
    }

    function calculatePresentValue(
        LPMath.PresentValueParams memory _params
    ) external pure returns (uint256) {
        return LPMath.calculatePresentValue(_params);
    }

    function calculateDistributeExcessIdleShareProceeds(
        LPMath.DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves,
        int256 _netCurveTrade
    ) external pure returns (uint256) {
        return
            LPMath.calculateDistributeExcessIdleShareProceeds(
                _params,
                _originalEffectiveShareReserves,
                _netCurveTrade
            );
    }

    function calculateMaxShareReservesDelta(
        LPMath.DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves,
        int256 _netCurveTrade
    ) external pure returns (uint256) {
        return
            LPMath.calculateMaxShareReservesDelta(
                _params,
                _originalEffectiveShareReserves,
                _netCurveTrade
            );
    }
}
