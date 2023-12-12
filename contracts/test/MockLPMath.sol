// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { LpMath } from "contracts/src/libraries/LpMath.sol";

contract MockLpMath {
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
            LpMath.calculateUpdateLiquidity(
                _shareReserves,
                _shareAdjustment,
                _bondReserves,
                _minimumShareReserves,
                _shareReservesDelta
            );
    }

    function calculatePresentValue(
        LpMath.PresentValueParams memory _params
    ) external pure returns (uint256) {
        return LpMath.calculatePresentValue(_params);
    }

    function calculateDistributeExcessIdleWithdrawalSharesRedeemed(
        LpMath.DistributeExcessIdleParams memory _params,
        uint256 _shareReservesDelta
    ) external pure returns (uint256) {
        return
            LpMath.calculateDistributeExcessIdleWithdrawalSharesRedeemed(
                _params,
                _shareReservesDelta
            );
    }

    function calculateDistributeExcessIdleShareProceeds(
        LpMath.DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves
    ) external pure returns (uint256) {
        return
            LpMath.calculateDistributeExcessIdleShareProceeds(
                _params,
                _originalEffectiveShareReserves
            );
    }

    function calculateMaxShareReservesDelta(
        LpMath.DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves
    ) external pure returns (uint256) {
        return
            LpMath.calculateMaxShareReservesDelta(
                _params,
                _originalEffectiveShareReserves
            );
    }
}
