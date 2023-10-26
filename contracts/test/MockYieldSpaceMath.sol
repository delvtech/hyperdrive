// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { YieldSpaceMath } from "../src/libraries/YieldSpaceMath.sol";

contract MockYieldSpaceMath {
    function calculateBondsOutGivenSharesInUnderestimate(
        uint256 z,
        uint256 y,
        uint256 dz,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath
            .calculateBondsOutGivenSharesInUnderestimate(z, y, dz, t, c, mu);
        return result;
    }

    function calculateSharesInGivenBondsOutOverestimate(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath
            .calculateSharesInGivenBondsOutOverestimate(z, y, dy, t, c, mu);
        return result;
    }

    function calculateSharesInGivenBondsOutUnderestimate(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath
            .calculateSharesInGivenBondsOutUnderestimate(z, y, dy, t, c, mu);
        return result;
    }

    function calculateSharesOutGivenBondsInUnderestimate(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath
            .calculateSharesOutGivenBondsInUnderestimate(z, y, dy, t, c, mu);
        return result;
    }

    function calculateMaxBuy(
        uint256 z,
        uint256 y,
        uint256 t,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        uint256 result1 = YieldSpaceMath.calculateMaxBuy(z, y, t, c, mu);
        return result1;
    }

    function modifiedYieldSpaceConstantOverestimate(
        uint256 c,
        uint256 mu,
        uint256 z,
        uint256 t,
        uint256 y
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.modifiedYieldSpaceConstantOverestimate(
            c,
            mu,
            z,
            t,
            y
        );
        return result;
    }

    function modifiedYieldSpaceConstantUnderestimate(
        uint256 c,
        uint256 mu,
        uint256 z,
        uint256 t,
        uint256 y
    ) external pure returns (uint256) {
        uint256 result = YieldSpaceMath.modifiedYieldSpaceConstantUnderestimate(
            c,
            mu,
            z,
            t,
            y
        );
        return result;
    }
}
