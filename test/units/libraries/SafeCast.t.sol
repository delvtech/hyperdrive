// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "contracts/src/libraries/SafeCast.sol";
import "forge-std/Vm.sol";
import { MockSafeCast } from "contracts/test/MockSafeCast.sol";
import { BaseTest } from "test/utils/BaseTest.sol";

contract SafeCastTest is BaseTest {
    function testSafeCastToUint128(uint256 num) public {
        MockSafeCast mock = new MockSafeCast();

        if (num > (2 ** 128 - 1)) {
            vm.expectRevert();
            mock.toUint128(num);
        } else {
            uint128 cast_num = mock.toUint128(num);
            assertEq(cast_num, uint128(num));
        }
    }

    function test_toUint128() public {
        MockSafeCast mock = new MockSafeCast();

        uint128 cast_num = mock.toUint128(0);
        assertEq(cast_num, uint128(0));
        cast_num = mock.toUint128(1);
        assertEq(cast_num, uint128(1));
        cast_num = mock.toUint128(2 ** 128 - 1);
        assertEq(cast_num, uint128(2 ** 128 - 1));

        vm.expectRevert();
        mock.toUint128(2 ** 128);

        vm.expectRevert();
        mock.toUint128(2 ** 256 - 1);

        vm.expectRevert();
        mock.toUint128(2 ** 136);

        vm.expectRevert();
        mock.toUint128(2 ** 255);
    }

    function test_toUint224() public {
        MockSafeCast mock = new MockSafeCast();

        uint224 cast_num = mock.toUint224(0);
        assertEq(cast_num, uint224(0));
        cast_num = mock.toUint224(1);
        assertEq(cast_num, uint224(1));
        cast_num = mock.toUint224(2 ** 224 - 1);
        assertEq(cast_num, uint224(2 ** 224 - 1));

        vm.expectRevert();
        mock.toUint224(2 ** 224);

        vm.expectRevert();
        mock.toUint224(2 ** 256 - 1);

        vm.expectRevert();
        mock.toUint224(2 ** 240);

        vm.expectRevert();
        mock.toUint224(2 ** 255);
    }
}
