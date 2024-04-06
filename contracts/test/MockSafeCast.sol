// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { SafeCast } from "../src/libraries/SafeCast.sol";

contract MockSafeCast {
    function toUint112(uint256 x) external pure returns (uint112 y) {
        y = SafeCast.toUint112(x);
    }

    function toUint128(uint256 x) external pure returns (uint128 y) {
        y = SafeCast.toUint128(x);
    }

    function toInt128(uint256 x) external pure returns (int128 y) {
        y = SafeCast.toInt128(x);
    }

    function toInt128(int256 x) external pure returns (int128 y) {
        y = SafeCast.toInt128(x);
    }

    function toInt256(uint256 x) external pure returns (int256 y) {
        y = SafeCast.toInt256(x);
    }
}
