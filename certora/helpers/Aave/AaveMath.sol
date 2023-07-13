// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.18;

import {FixedPointMath} from "../../../contracts/src/libraries/FixedPointMath.sol";

library AaveMath {
    uint256 internal constant RAY = 1e27;

    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (FixedPointMath.mulDivUp(a, b, RAY));
    }

    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (FixedPointMath.mulDivUp(a, RAY, b));
    }

    /// @dev source : OZ SafeCast library
    function toUint128(uint256 value) internal pure returns (uint128) {
        require(value <= type(uint128).max, "SafeCast: value doesn't fit in 128 bits");
        return uint128(value);
    }
}