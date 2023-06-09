// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "contracts/test/MockFixedPointMath.sol";
import "test/3rdPartyLibs/LogExpMath.sol";
import "test/3rdPartyLibs/BalancerErrors.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";

contract FixedPointMathTest is Test {
    function setUp() public {}

    function test_add() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        assertEq(mockFixedPointMath.add(1e18, 1e18), 2e18);
        assertEq(mockFixedPointMath.add(1e18, 0), 1e18);
        assertEq(mockFixedPointMath.add(0, 1e18), 1e18);
        assertEq(mockFixedPointMath.add(0, 0), 0);
    }

    function test_fail_add_overflow() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        vm.expectRevert(stdError.arithmeticError);
        mockFixedPointMath.add(type(uint256).max, 1e18);
    }

    function test_sub() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        assertEq(mockFixedPointMath.sub(1e18, 1e18), 0);
        assertEq(mockFixedPointMath.sub(1e18, 0), 1e18);
        assertEq(mockFixedPointMath.sub(2e18, 1e18), 1e18);
        assertEq(mockFixedPointMath.sub(0, 0), 0);
    }

    function test_fail_sub_overflow() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        vm.expectRevert(Errors.FixedPointMath_SubOverflow.selector);
        mockFixedPointMath.sub(0, 1e18);
    }

    function test_mulDown() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        assertEq(mockFixedPointMath.mulDown(2.5e18, 0.5e18), 1.25e18);
        assertEq(mockFixedPointMath.mulDown(3e18, 1e18), 3e18);
        assertEq(mockFixedPointMath.mulDown(369, 271), 0);
        assertEq(mockFixedPointMath.mulDown(0, 1e18), 0);
        assertEq(mockFixedPointMath.mulDown(1e18, 0), 0);
        assertEq(mockFixedPointMath.mulDown(0, 0), 0);
    }

    function test_mulUp() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        assertEq(mockFixedPointMath.mulUp(2.5e18, 0.5e18), 1.25e18);
        assertEq(mockFixedPointMath.mulUp(3e18, 1e18), 3e18);
        assertEq(mockFixedPointMath.mulUp(369, 271), 1);
        assertEq(mockFixedPointMath.mulUp(0, 1e18), 0);
        assertEq(mockFixedPointMath.mulUp(1e18, 0), 0);
        assertEq(mockFixedPointMath.mulUp(0, 0), 0);
    }

    function test_divDown() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        assertEq(mockFixedPointMath.divDown(1.25e18, 0.5e18), 2.5e18);
        assertEq(mockFixedPointMath.divDown(3e18, 1e18), 3e18);
        assertEq(mockFixedPointMath.divDown(2, 100000000000000e18), 0);
        assertEq(mockFixedPointMath.divDown(0, 1e18), 0);
    }

    function test_fail_divDown_zero_denominator() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        vm.expectRevert();
        mockFixedPointMath.divDown(1e18, 0);
    }

    function test_divUp() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        assertEq(mockFixedPointMath.divUp(1.25e18, 0.5e18), 2.5e18);
        assertEq(mockFixedPointMath.divUp(3e18, 1e18), 3e18);
        assertEq(mockFixedPointMath.divUp(2, 100000000000000e18), 1);
        assertEq(mockFixedPointMath.divUp(0, 1e18), 0);
    }

    function test_fail_divUp_zero_denominator() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        // TODO: Should we have an error for divide by zero?
        vm.expectRevert();
        mockFixedPointMath.divUp(1e18, 0);
    }

    function test_mulDivDown() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        assertEq(mockFixedPointMath.mulDivDown(2.5e27, 0.5e27, 1e27), 1.25e27);
        assertEq(mockFixedPointMath.mulDivDown(2.5e18, 0.5e18, 1e18), 1.25e18);
        assertEq(mockFixedPointMath.mulDivDown(2.5e8, 0.5e8, 1e8), 1.25e8);
        assertEq(mockFixedPointMath.mulDivDown(369, 271, 1e2), 999);
        assertEq(mockFixedPointMath.mulDivDown(1e27, 1e27, 2e27), 0.5e27);
        assertEq(mockFixedPointMath.mulDivDown(1e18, 1e18, 2e18), 0.5e18);
        assertEq(mockFixedPointMath.mulDivDown(1e8, 1e8, 2e8), 0.5e8);
        assertEq(mockFixedPointMath.mulDivDown(2e27, 3e27, 2e27), 3e27);
        assertEq(mockFixedPointMath.mulDivDown(3e18, 2e18, 3e18), 2e18);
        assertEq(mockFixedPointMath.mulDivDown(2e8, 3e8, 2e8), 3e8);
        assertEq(mockFixedPointMath.mulDivDown(0, 1e18, 1e18), 0);
        assertEq(mockFixedPointMath.mulDivDown(1e18, 0, 1e18), 0);
        assertEq(mockFixedPointMath.mulDivDown(0, 0, 1e18), 0);
    }

    function test_fail_mulDivDown_zero_denominator() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        // TODO: Should we have an error for divide by zero?
        vm.expectRevert();
        mockFixedPointMath.mulDivDown(1e18, 1e18, 0);
    }

    function test_mulDivUp() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        assertEq(mockFixedPointMath.mulDivUp(2.5e27, 0.5e27, 1e27), 1.25e27);
        assertEq(mockFixedPointMath.mulDivUp(2.5e18, 0.5e18, 1e18), 1.25e18);
        assertEq(mockFixedPointMath.mulDivUp(2.5e8, 0.5e8, 1e8), 1.25e8);
        assertEq(mockFixedPointMath.mulDivUp(369, 271, 1e2), 1000);
        assertEq(mockFixedPointMath.mulDivUp(1e27, 1e27, 2e27), 0.5e27);
        assertEq(mockFixedPointMath.mulDivUp(1e18, 1e18, 2e18), 0.5e18);
        assertEq(mockFixedPointMath.mulDivUp(1e8, 1e8, 2e8), 0.5e8);
        assertEq(mockFixedPointMath.mulDivUp(2e27, 3e27, 2e27), 3e27);
        assertEq(mockFixedPointMath.mulDivUp(3e18, 2e18, 3e18), 2e18);
        assertEq(mockFixedPointMath.mulDivUp(2e8, 3e8, 2e8), 3e8);
        assertEq(mockFixedPointMath.mulDivUp(0, 1e18, 1e18), 0);
        assertEq(mockFixedPointMath.mulDivUp(1e18, 0, 1e18), 0);
        assertEq(mockFixedPointMath.mulDivUp(0, 0, 1e18), 0);
    }

    function test_fail_mulDivUp_zero_denominator() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        // TODO: Should we have an error for divide by zero?
        vm.expectRevert();
        mockFixedPointMath.mulDivUp(1e18, 1e18, 0);
    }

    function test_pow() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();

        uint256 x = 0;
        uint256 y = 0;
        uint256 result = mockFixedPointMath.pow(x, y);
        uint256 expected = LogExpMath.pow(x, y);
        assertEq(result, expected);

        x = 300000000000000000000000;
        y = 0;
        result = mockFixedPointMath.pow(x, y);
        expected = LogExpMath.pow(x, y);
        assertEq(result, expected);

        x = 0;
        y = 977464155968402951;
        result = mockFixedPointMath.pow(x, y);
        expected = LogExpMath.pow(x, y);
        assertEq(result, expected);

        x = 300000000000000000000000;
        y = 977464155968402951;
        result = mockFixedPointMath.pow(x, y);
        expected = LogExpMath.pow(x, y);
        assertApproxEqAbs(result, expected, 1e5 wei);

        x = 180000000000000000000000;
        y = 977464155968402951;
        result = mockFixedPointMath.pow(x, y);
        expected = LogExpMath.pow(x, y);
        assertApproxEqAbs(result, expected, 1e5 wei);

        x = 165891671009915386326945;
        y = 1023055417320413264;
        result = mockFixedPointMath.pow(x, y);
        expected = LogExpMath.pow(x, y);
        assertApproxEqAbs(result, expected, 1e5 wei);

        x = 77073744241129234405745;
        y = 1023055417320413264;
        result = mockFixedPointMath.pow(x, y);
        expected = LogExpMath.pow(x, y);
        assertApproxEqAbs(result, expected, 1e5 wei);

        x = 18458206546438581254928;
        y = 1023055417320413264;
        result = mockFixedPointMath.pow(x, y);
        expected = LogExpMath.pow(x, y);
        assertApproxEqAbs(result, expected, 1e5 wei);
    }

    function test_exp() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        assertEq(mockFixedPointMath.exp(1e18), 2.718281828459045235e18);
        assertEq(mockFixedPointMath.exp(0), 1e18);
        assertEq(mockFixedPointMath.exp(-1e18), 0.367879441171442321e18);
        assertEq(mockFixedPointMath.exp(-42139678854452767551), 0);
    }

    function test_fail_exp_negative_or_zero_input() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        vm.expectRevert(Errors.FixedPointMath_InvalidExponent.selector);
        mockFixedPointMath.exp(135305999368893231589);
    }

    function test_ln() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        assertEq(mockFixedPointMath.ln(1e18), 0);
        assertEq(mockFixedPointMath.ln(1000000e18), 13.815510557964274104e18);
    }

    function test_fail_ln_negative_or_zero_input() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        vm.expectRevert(Errors.FixedPointMath_NegativeOrZeroInput.selector);
        mockFixedPointMath.ln(0);
    }

    function test_updateWeightedAverage() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        assertEq(
            mockFixedPointMath.updateWeightedAverage(
                1e18,
                1e18,
                1e18,
                1e18,
                true
            ),
            1e18
        );
        assertEq(
            mockFixedPointMath.updateWeightedAverage(
                1e18,
                1e18,
                1e18,
                1e18,
                false
            ),
            0
        );
        assertEq(
            mockFixedPointMath.updateWeightedAverage(
                1e18,
                2e18,
                1e18,
                1e18,
                false
            ),
            1e18
        );
    }

    function test_differential_fuzz_pow(uint256 x, uint256 y) public {
        vm.assume(x < 2 ** 255);
        vm.assume(y < 1);
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        uint256 result = mockFixedPointMath.pow(x, y);
        uint256 expected = LogExpMath.pow(x, y);
        assertApproxEqAbs(result, expected, 1e5 wei);
    }

    /// @dev This test is to check that the pow function returns 1e18 when the exponent is 0
    function test_differential_fuzz_pow_zero(uint256 x) public {
        vm.assume(x > 0);
        vm.assume(x < 2 ** 255);
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        uint256 result = mockFixedPointMath.pow(x, 0);
        assertEq(result, 1e18);
    }

    function test_updateWeightedAverageMathBoundsExceeded() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();

        uint256 newAverage = mockFixedPointMath.updateWeightedAverage(
            0xffffffffffffffff,
            0xde0b6b3a7640004,
            0x10000000000000001,
            1,
            true
        );

        assertEq(newAverage, 0xfffffffffffffffe);

    /*
        Average = 0xffffffffffffffff = 2^64 - 1
        totWeight = 0xde0b6b3a7640004 = 10^18 + 4
        Delta = 0x10000000000000001 = 2^64 + 1
        deltaW = 1
        isAdd = true
        New average = 0xfffffffffffffffe = Average - 1
    */
    }
}
