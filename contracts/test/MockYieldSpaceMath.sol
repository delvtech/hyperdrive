// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { YieldSpaceMath } from "../src/libraries/YieldSpaceMath.sol";

contract MockYieldSpaceMath {
    function calculateBondsOutGivenSharesInDown(
        uint256 z,
        uint256 y,
        uint256 dz,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateBondsOutGivenSharesInDown(
            z,
            y,
            dz,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesInGivenBondsOutUp(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateSharesInGivenBondsOutUp(
            z,
            y,
            dy,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesInGivenBondsOutDown(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateSharesInGivenBondsOutDown(
            z,
            y,
            dy,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesOutGivenBondsInDown(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.calculateSharesOutGivenBondsInDown(
            z,
            y,
            dy,
            t,
            c,
            mu
        );
        return result;
    }

    function calculateSharesOutGivenBondsInDownSafe(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256, bool) {
        (uint256 result1, bool result2) = YieldSpaceMath
            .calculateSharesOutGivenBondsInDownSafe(z, y, dy, t, c, mu);
        return (result1, result2);
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

    function calculateMaxSell(
        uint256 z,
        uint256 y,
        uint256 zMin,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256, uint256) {
        (uint256 result1, uint256 result2) = YieldSpaceMath.calculateMaxSell(
            z,
            y,
            zMin,
            t,
            c,
            mu
        );
        return (result1, result2);
    }

    function kUp(
        uint256 z,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.kUp(z, y, t, c, mu);
        return result;
    }

    function kDown(
        uint256 z,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.kDown(z, y, t, c, mu);
        return result;
    }
}
