// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { YieldSpaceMath } from "../src/libraries/YieldSpaceMath.sol";

contract MockYieldSpaceMath {
    function calculateBondsOutGivenSharesInDown(
        uint256 z_e,
        uint256 y,
        uint256 dz,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateBondsOutGivenSharesInDown(
            z_e,
            y,
            dz,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesInGivenBondsOutUp(
        uint256 z_e,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateSharesInGivenBondsOutUp(
            z_e,
            y,
            dy,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesInGivenBondsOutDown(
        uint256 z_e,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateSharesInGivenBondsOutDown(
            z_e,
            y,
            dy,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesOutGivenBondsInDown(
        uint256 z_e,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateSharesOutGivenBondsInDown(
            z_e,
            y,
            dy,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesOutGivenBondsInDownSafe(
        uint256 z_e,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256, bool) {
        (uint256 result1, bool result2) = YieldSpaceMath
            .calculateSharesOutGivenBondsInDownSafe(z_e, y, dy, t, c, mu);
        return (result1, result2);
    }

    function calculateMaxBuySharesIn(
        uint256 z_e,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result1 = YieldSpaceMath.calculateMaxBuySharesIn(
            z_e,
            y,
            t,
            c,
            mu
        );
        return result1;
    }

    function calculateMaxBuyBondsOut(
        uint256 z_e,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result1 = YieldSpaceMath.calculateMaxBuyBondsOut(
            z_e,
            y,
            t,
            c,
            mu
        );
        return result1;
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
        uint256 z_e,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.kUp(z_e, y, t, c, mu);
        return result;
    }

    function kDown(
        uint256 z_e,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.kDown(z_e, y, t, c, mu);
        return result;
    }
}
