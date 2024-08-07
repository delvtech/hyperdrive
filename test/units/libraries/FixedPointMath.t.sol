// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdError, Test } from "forge-std/Test.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { MockFixedPointMath } from "../../../contracts/test/MockFixedPointMath.sol";
import { LogExpMath } from "../../3rdPartyLibs/LogExpMath.sol";
import { BalancerErrors } from "../../3rdPartyLibs/BalancerErrors.sol";
import { Lib } from "../../utils/Lib.sol";

contract FixedPointMathTest is Test {
    using FixedPointMath for uint256;
    using Lib for *;

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
        vm.expectRevert(IHyperdrive.ExpInvalidExponent.selector);
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
        vm.expectRevert(IHyperdrive.LnInvalidInput.selector);
        mockFixedPointMath.ln(0);
    }

    function test_updateWeightedAverage() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        assertEq(
            mockFixedPointMath.updateWeightedAverage(2e18, 1e18, 3e18, 0, true),
            2e18
        );
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
        assertEq(
            mockFixedPointMath.updateWeightedAverage(
                100e18,
                10e18,
                200e18,
                10e18,
                true
            ),
            150e18
        );
    }

    // This test verifies that update weighted average always performs as a
    // a weighted average with the expected inputs. This just means that if
    // the current average is A, the current weight is W, and the new value is
    // a, and the new weight is w, then the new average satisfies the property:
    //
    // min(a, A) <= (A * W + a * w) / (W + w) <= max(a, A)
    //
    // This property is true for the weighted average when computed with perfect
    // precision, but it needs to be verified for the fixed point math
    // implementation. This property isn't held when `isAdding = false` since
    // removing a large value from the average can reveal points in the data
    // that were previously less influential.
    function test_updateWeightedAverage_fuzz(
        uint256 average,
        uint256 totalWeight,
        uint256 delta,
        uint256 deltaWeight
    ) public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();

        // Normalize the inputs to a reasonable range for the uses of the
        // weighted average in the codebase.
        average = average.normalizeToRange(1e9, 100_000_000e18);
        totalWeight = totalWeight.normalizeToRange(1e9, 100_000_000e18);
        delta = delta.normalizeToRange(1e9, 100_000_000e18);
        deltaWeight = deltaWeight.normalizeToRange(1e9, 100_000_000e18);

        // Calculate the weighted average.
        uint256 updatedAverage = mockFixedPointMath.updateWeightedAverage(
            average,
            totalWeight,
            delta,
            deltaWeight,
            true
        );

        // Ensure that the weighted average is actually an average.
        assertGe(updatedAverage, average.min(delta));
        assertLe(updatedAverage, average.max(delta));
    }

    function test_differential_fuzz_pow(uint256 x, uint256 y) public {
        x = x.normalizeToRange(0, 2 ** 255);
        // TODO: If this is updated to a larger range (like [0, 1e18]), the
        // tolerance becomes very large.
        y = y.normalizeToRange(0, 1);
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        uint256 result = mockFixedPointMath.pow(x, y);
        uint256 expected = LogExpMath.pow(x, y);
        assertApproxEqAbs(result, expected, 1e5 wei);
    }

    /// @dev This test is to check that the pow function returns 1e18 when the exponent is 0
    function test_differential_fuzz_pow_zero(uint256 x) public {
        x = x.normalizeToRange(0, 2 ** 255);
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockFixedPointMath mockFixedPointMath = new MockFixedPointMath();
        uint256 result = mockFixedPointMath.pow(x, 0);
        assertEq(result, 1e18);
    }
}
