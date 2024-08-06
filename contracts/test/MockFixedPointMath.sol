/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { FixedPointMath } from "../src/libraries/FixedPointMath.sol";

contract MockFixedPointMath {
    using FixedPointMath for uint256;

    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 d
    ) external pure returns (uint256 z) {
        uint256 result = FixedPointMath.mulDivDown(x, y, d);
        return result;
    }

    function mulDown(uint256 a, uint256 b) external pure returns (uint256) {
        uint256 result = FixedPointMath.mulDown(a, b);
        return result;
    }

    function divDown(uint256 a, uint256 b) external pure returns (uint256) {
        uint256 result = FixedPointMath.divDown(a, b);
        return result;
    }

    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 d
    ) external pure returns (uint256 z) {
        uint256 result = FixedPointMath.mulDivUp(x, y, d);
        return result;
    }

    function mulUp(uint256 a, uint256 b) external pure returns (uint256) {
        uint256 result = FixedPointMath.mulUp(a, b);
        return result;
    }

    function divUp(uint256 a, uint256 b) external pure returns (uint256) {
        uint256 result = FixedPointMath.divUp(a, b);
        return result;
    }

    function pow(uint256 x, uint256 y) external pure returns (uint256) {
        uint256 result = FixedPointMath.pow(x, y);
        return result;
    }

    function exp(int256 x) external pure returns (int256 r) {
        int256 result = FixedPointMath.exp(x);
        return result;
    }

    function ln(int256 x) external pure returns (int256) {
        int256 result = FixedPointMath.ln(x);
        return result;
    }

    function updateWeightedAverage(
        uint256 _average,
        uint256 _totalWeight,
        uint256 _delta,
        uint256 _deltaWeight,
        bool _isAdding
    ) external pure returns (uint256 average) {
        uint256 result = FixedPointMath.updateWeightedAverage(
            _average,
            _totalWeight,
            _delta,
            _deltaWeight,
            _isAdding
        );
        return result;
    }
}
