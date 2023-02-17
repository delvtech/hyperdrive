// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { YieldSpaceMath } from "contracts/libraries/YieldSpaceMath.sol";

contract MockYieldSpaceMath {
    function calculateOutGivenIn(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 bondReserveAdjustment,
        uint256 amountIn,
        uint256 stretchedTimeElapsed,
        uint256 c,
        uint256 mu,
        bool isBondIn
    ) external returns (uint256) {
        uint256 result = YieldSpaceMath.calculateOutGivenIn(
            shareReserves,
            bondReserves,
            bondReserveAdjustment,
            amountIn,
            stretchedTimeElapsed,
            c,
            mu,
            isBondIn
        );
        return result;
    }

    function calculateInGivenOut(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 bondReserveAdjustment,
        uint256 amountOut,
        uint256 stretchedTimeElapsed,
        uint256 c,
        uint256 mu,
        bool isBaseOut
    ) external returns (uint256) {
        uint256 result = YieldSpaceMath.calculateInGivenOut(
            shareReserves,
            bondReserves,
            bondReserveAdjustment,
            amountOut,
            stretchedTimeElapsed,
            c,
            mu,
            isBaseOut
        );
        return result;
    }
}
