// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "contracts/src/libraries/SafeCast.sol";
import "forge-std/Vm.sol";
import {BaseTest } from "test/utils/BaseTest.sol";

contract SafeCastTest is BaseTest {
    function testSafeCastToUint128(uint256 num) public {
        if (num >= (2**128-1)) {
            vm.expectRevert();
            SafeCast.toUint128(num);
        } else {
            uint128 cast_num = SafeCast.toUint128(num);
            assertEq(cast_num, uint128(num));
        }
    }
}