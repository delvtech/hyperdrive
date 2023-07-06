// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../src/libraries/SafeCast.sol";

contract MockSafeCast {
    function toUint128(uint256 x) external pure returns (uint128) {
        uint128 y = SafeCast.toUint128(x);
        return y;
    }

    function toUint224(uint256 x) external pure returns (uint224) {
        uint224 y = SafeCast.toUint224(x);
        return y;
    }
}
