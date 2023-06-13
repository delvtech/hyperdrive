// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { YieldSpaceMath } from "../src/libraries/YieldSpaceMath.sol";

contract MockYieldSpaceMath {
    function calculateBondsInGivenSharesOut(
        uint256 z,
        uint256 y,
        uint256 dz,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateBondsInGivenSharesOut(
            z,
            y,
            dz,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateBondsOutGivenSharesIn(
        uint256 z,
        uint256 y,
        uint256 dz,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateBondsOutGivenSharesIn(
            z,
            y,
            dz,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesInGivenBondsOut(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateSharesInGivenBondsOut(
            z,
            y,
            dy,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesOutGivenBondsIn(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateSharesOutGivenBondsIn(
            z,
            y,
            dy,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateMaxBuy(
        uint256 z,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256, uint256) {
        (uint256 result1, uint256 result2) = YieldSpaceMath.calculateMaxBuy(
            z,
            y,
            t,
            c,
            mu
        );
        return (result1, result2);
    }

    function modifiedYieldSpaceConstant(
        uint256 cDivMu,
        uint256 mu,
        uint256 z,
        uint256 t,
        uint256 y
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.modifiedYieldSpaceConstant(
            cDivMu,
            mu,
            z,
            t,
            y
        );
        return result;
    }
}
