// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../src/libraries/SafeCast.sol";

contract MockSafeCast {
    function toUint128(uint256 x) external pure returns (uint128 y) {
        y = SafeCast.toUint128(x);
    }

    function toUint224(uint256 x) external pure returns (uint224 y) {
        y = SafeCast.toUint224(x);
    }
}
