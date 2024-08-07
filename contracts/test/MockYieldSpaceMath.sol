// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { YieldSpaceMath } from "../src/libraries/YieldSpaceMath.sol";

contract MockYieldSpaceMath {
    function calculateBondsOutGivenSharesInDown(
        uint256 ze,
        uint256 y,
        uint256 dz,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateBondsOutGivenSharesInDown(
            ze,
            y,
            dz,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesInGivenBondsOutUp(
        uint256 ze,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateSharesInGivenBondsOutUp(
            ze,
            y,
            dy,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesInGivenBondsOutDown(
        uint256 ze,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateSharesInGivenBondsOutDown(
            ze,
            y,
            dy,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesOutGivenBondsInDown(
        uint256 ze,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateSharesOutGivenBondsInDown(
            ze,
            y,
            dy,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesOutGivenBondsInDownSafe(
        uint256 ze,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256, bool) {
        (uint256 result1, bool result2) = YieldSpaceMath
            .calculateSharesOutGivenBondsInDownSafe(ze, y, dy, t, c, mu);
        return (result1, result2);
    }

    function calculateMaxBuySharesInSafe(
        uint256 ze,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256, bool) {
        (uint256 result1, bool result2) = YieldSpaceMath
            .calculateMaxBuySharesInSafe(ze, y, t, c, mu);
        return (result1, result2);
    }

    function calculateMaxBuyBondsOutSafe(
        uint256 ze,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256, bool) {
        (uint256 result1, bool result2) = YieldSpaceMath
            .calculateMaxBuyBondsOutSafe(ze, y, t, c, mu);
        return (result1, result2);
    }

    function calculateMaxSellBondsInSafe(
        uint256 z,
        int256 zeta,
        uint256 y,
        uint256 zMin,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256, bool) {
        (uint256 result1, bool result2) = YieldSpaceMath
            .calculateMaxSellBondsInSafe(z, zeta, y, zMin, t, c, mu);
        return (result1, result2);
    }

    function kUp(
        uint256 ze,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.kUp(ze, y, t, c, mu);
        return result;
    }

    function kDown(
        uint256 ze,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.kDown(ze, y, t, c, mu);
        return result;
    }
}
