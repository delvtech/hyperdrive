// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Vm } from "forge-std/Vm.sol";
import { SafeCast } from "../../../contracts/src/libraries/SafeCast.sol";
import { MockSafeCast } from "../../../contracts/test/MockSafeCast.sol";
import { BaseTest } from "../../utils/BaseTest.sol";

contract SafeCastTest is BaseTest {
    function test_toUint128_fuzz(uint256 num) public {
        MockSafeCast mock = new MockSafeCast();

        if (num > type(uint128).max) {
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
        cast_num = mock.toUint128(type(uint128).max);
        assertEq(cast_num, uint128(type(uint128).max));

        vm.expectRevert();
        mock.toUint128(type(uint128).max + 1);

        vm.expectRevert();
        mock.toUint128(type(uint256).max);

        vm.expectRevert();
        mock.toUint128(type(uint136).max);

        vm.expectRevert();
        mock.toUint128(2 ** 255);
    }

    function test_toUint112_fuzz(uint256 num) public {
        MockSafeCast mock = new MockSafeCast();

        if (num > type(uint112).max) {
            vm.expectRevert();
            mock.toUint112(num);
        } else {
            uint128 cast_num = mock.toUint112(num);
            assertEq(cast_num, uint112(num));
        }
    }

    function test_toUint112() public {
        MockSafeCast mock = new MockSafeCast();

        uint128 cast_num = mock.toUint112(0);
        assertEq(cast_num, uint112(0));
        cast_num = mock.toUint112(1);
        assertEq(cast_num, uint112(1));
        cast_num = mock.toUint112(type(uint112).max);
        assertEq(cast_num, uint112(type(uint112).max));

        vm.expectRevert();
        mock.toUint128(type(uint112).max + 1);

        vm.expectRevert();
        mock.toUint128(type(uint256).max);

        vm.expectRevert();
        mock.toUint128(type(uint120).max);

        vm.expectRevert();
        mock.toUint128(2 ** 255);
    }

    function test_toUint256() public {
        MockSafeCast mock = new MockSafeCast();

        uint256 cast_num = mock.toUint256(0);
        assertEq(cast_num, uint256(0));
        cast_num = mock.toUint256(1);
        assertEq(cast_num, uint256(1));
        cast_num = mock.toUint256(type(int256).max);
        assertEq(cast_num, uint256(type(int256).max));

        vm.expectRevert();
        mock.toUint256(-1);

        vm.expectRevert();
        mock.toUint256(type(int256).min);
    }

    function test_toInt128_fromUint256_fuzz(uint256 num) public {
        MockSafeCast mock = new MockSafeCast();

        if (num > uint128(type(int128).max)) {
            vm.expectRevert();
            mock.toInt128(num);
        } else {
            int128 cast_num = mock.toInt128(num);
            assertEq(cast_num, int128(uint128(num)));
        }
    }

    function test_toInt128_fromUint256() public {
        MockSafeCast mock = new MockSafeCast();

        int128 cast_num = mock.toInt128(uint256(0));
        assertEq(cast_num, int128(0));
        cast_num = mock.toInt128(uint256(1));
        assertEq(cast_num, int128(1));
        cast_num = mock.toInt128(type(int128).max);
        assertEq(cast_num, int128(type(int128).max));

        vm.expectRevert();
        mock.toInt128(uint128(type(int128).max) + 1);

        vm.expectRevert();
        mock.toInt128(type(uint256).max);

        vm.expectRevert();
        mock.toInt128(uint136(type(int136).max));

        vm.expectRevert();
        mock.toInt128(2 ** 255);
    }

    function test_toInt128_fromInt256_fuzz(int256 num) public {
        MockSafeCast mock = new MockSafeCast();

        if (num < type(int128).min || num > type(int128).max) {
            vm.expectRevert();
            mock.toInt128(num);
        } else {
            int128 cast_num = mock.toInt128(num);
            assertEq(cast_num, int128(num));
        }
    }

    function test_toInt128_fromInt256() public {
        MockSafeCast mock = new MockSafeCast();

        int128 cast_num = mock.toInt128(int256(0));
        assertEq(cast_num, int128(0));
        cast_num = mock.toInt128(int256(1));
        assertEq(cast_num, int128(1));
        cast_num = mock.toInt128(int256(-1));
        assertEq(cast_num, int128(-1));
        cast_num = mock.toInt128(type(int128).max);
        assertEq(cast_num, int128(type(int128).max));
        cast_num = mock.toInt128(type(int128).min);
        assertEq(cast_num, int128(type(int128).min));

        vm.expectRevert();
        mock.toInt128(type(int128).max + 1);

        vm.expectRevert();
        mock.toInt128(type(int128).min - 1);

        vm.expectRevert();
        mock.toInt128(type(int256).max);

        vm.expectRevert();
        mock.toInt128(type(int256).min);

        vm.expectRevert();
        mock.toInt128(uint136(type(int136).max));

        vm.expectRevert();
        mock.toInt128(uint136(type(int136).min));

        vm.expectRevert();
        mock.toInt128(2 ** 255);
    }

    function test_toInt256_fuzz(uint256 num) public {
        MockSafeCast mock = new MockSafeCast();

        if (num > uint256(type(int256).max)) {
            vm.expectRevert();
            mock.toInt256(num);
        } else {
            int256 cast_num = mock.toInt256(num);
            assertEq(cast_num, int256(num));
        }
    }

    function test_toInt256() public {
        MockSafeCast mock = new MockSafeCast();

        int256 cast_num = mock.toInt256(0);
        assertEq(cast_num, int256(0));
        cast_num = mock.toInt256(1);
        assertEq(cast_num, int256(1));
        cast_num = mock.toInt256(uint256(type(int256).max));
        assertEq(cast_num, int256(type(int256).max));

        vm.expectRevert();
        mock.toInt256(type(uint256).max);

        vm.expectRevert();
        mock.toInt256(2 ** 255);
    }
}
