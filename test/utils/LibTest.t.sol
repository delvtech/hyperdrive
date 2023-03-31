// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { Lib } from "./Lib.sol";

contract LibTest is Test {
    using Lib for *;

    // NOTE: We use uint128 inputs to avoid overflows.
    function test_normalize_to_range_uint256(
        uint256 value,
        uint128 min,
        uint128 max
    ) external {
        if (min > max) {
            vm.expectRevert("Lib: min > max");
            value.normalizeToRange(min, max);
        } else {
            uint256 result = value.normalizeToRange(min, max);
            assertGe(result, min);
            assertLe(result, max);
        }
    }

    // NOTE: We use int128 inputs to avoid overflows and underflows.
    function test_normalize_to_range_int256(
        int256 value,
        int128 min,
        int128 max
    ) external {
        if (min > max) {
            vm.expectRevert("Lib: min > max");
            value.normalizeToRange(min, max);
        } else {
            int256 result = value.normalizeToRange(min, max);
            assertGe(result, min);
            assertLe(result, max);
        }
    }
}
