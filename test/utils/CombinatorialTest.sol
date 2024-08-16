// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { HyperdriveTest } from "./HyperdriveTest.sol";
import { Lib } from "./Lib.sol";

contract CombinatorialTest is HyperdriveTest {
    enum CombinatorialTestKind {
        Fail,
        Success
    }

    CombinatorialTestKind internal __combinatorialTestKind =
        CombinatorialTestKind.Success;

    error ExpectedSuccess();
    error ExpectedFail();

    error UnassignedCatch();
    error UnassignedFail();

    error TestFail();

    bytes __error = abi.encodeWithSelector(UnassignedCatch.selector);
    bytes __fail_error = abi.encodeWithSelector(UnassignedFail.selector);

    modifier __combinatorial_setup() {
        __combinatorialTestKind = CombinatorialTestKind.Success;
        __error = abi.encodeWithSelector(UnassignedCatch.selector);
        __fail_error = abi.encodeWithSelector(UnassignedFail.selector);
        _;
    }

    modifier __combinatorial_success() {
        // If the test case was set as a fail we short-circuit the __success function
        if (__combinatorialTestKind == CombinatorialTestKind.Fail) {
            return;
        }
        _;
    }

    modifier __combinatorial_fail() {
        _;
        // Detect if the __fail call was caught
        if (
            Lib.neq(__error, abi.encodeWithSelector(UnassignedCatch.selector))
        ) {
            // If a __fail call was caught then a __fail_error must be assigned
            assertTrue(
                !checkEq0(
                    __fail_error,
                    abi.encodeWithSelector(UnassignedFail.selector)
                ),
                "__fail_error should be assigned"
            );
            // If the caught error and the expected error do not match then
            // cause a test revert
            if (Lib.neq(__error, __fail_error)) {
                assertEq(__error, __fail_error, "Expected different error");
            }

            // If an error was caught we set this so __success will short-circuit
            __combinatorialTestKind = CombinatorialTestKind.Fail;
        } else {
            assertEq(
                __fail_error,
                abi.encodeWithSelector(UnassignedFail.selector),
                "__fail_error should not be assigned"
            );
            assertEq(
                __error,
                abi.encodeWithSelector(UnassignedCatch.selector),
                "__error should not be assigned"
            );
        }
    }

    function setUp() public virtual override {
        super.setUp();
    }

    // @notice Generates a matrix of all of the different combinations of
    //         inputs for each row.
    // @dev In order to generate the full testing matrix, we need to generate
    //      cases for each value that use all of the input values. In order
    //      to do this, we segment the set of test cases into subsets for each
    //      entry
    // @param inputs A matrix of uint256 values that defines the inputs that
    //        will be used to generate combinations for each row. Increasing the
    //        number of inputs dramatically increases the amount of test cases
    //        that will be generated, so it's important to limit the amount of
    //        inputs to a small number of meaningful values. We use uint256 for
    //        generality, since uint256 can be converted to small width types.
    // @return The full testing matrix.
    function __matrix(
        uint256[][] memory inputs
    ) internal pure returns (uint256[][] memory result) {
        // Compute the divisors that will be used to compute the intervals for
        // every input row.
        uint256 base = 1;
        uint256[] memory intervalDivisors = new uint256[](inputs.length);
        for (uint256 i = 0; i < inputs.length; i++) {
            base *= inputs[i].length;
            intervalDivisors[i] = base;
        }
        // Generate the testing matrix.
        result = new uint256[][](base);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = new uint256[](inputs.length);
            for (uint256 j = 0; j < inputs.length; j++) {
                // The idea behind this calculation is that we split the set of
                // test cases into sections and assign one input value to each
                // section. For the first row, we'll create {inputs[0].length}
                // sections and assign these values to sections linearly. For
                // row 1, we'll create inputs[0].length * inputs[1].length
                // sections, and we'll assign the 0th input to the first
                // section, the 1st input to the second section, and continue
                // this process (wrapping around once we run out of input values
                // to allocate).
                //
                // The proof that each row of this procedure is unique is easy
                // using induction. Proving that every row is unique also shows
                // that the full test matrix has been covered.
                result[i][j] = inputs[j][
                    (i / (result.length / intervalDivisors[j])) %
                        inputs[j].length
                ];
            }
        }
        return result;
    }

    function _arr(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](2);
        array[0] = a;
        array[1] = b;
    }

    function _arr(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](3);
        array[0] = a;
        array[1] = b;
        array[2] = c;
    }

    function _arr(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](4);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
    }

    function _arr(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d,
        uint256 e
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](5);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
        array[4] = e;
    }

    function _arr(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d,
        uint256 e,
        uint256 f
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](6);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
        array[4] = e;
        array[5] = f;
    }

    function _arr(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d,
        uint256 e,
        uint256 f,
        uint256 g
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](7);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
        array[4] = e;
        array[5] = f;
        array[6] = g;
    }

    function _arr(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d,
        uint256 e,
        uint256 f,
        uint256 g,
        uint256 h
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](8);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
        array[4] = e;
        array[5] = f;
        array[6] = g;
        array[7] = h;
    }

    function _arr(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d,
        uint256 e,
        uint256 f,
        uint256 g,
        uint256 h,
        uint256 i
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](9);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
        array[4] = e;
        array[5] = f;
        array[6] = g;
        array[7] = h;
        array[8] = i;
    }

    function _arr(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d,
        uint256 e,
        uint256 f,
        uint256 g,
        uint256 h,
        uint256 i,
        uint256 j
    ) internal pure returns (uint256[] memory array) {
        array = new uint256[](10);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
        array[4] = e;
        array[5] = f;
        array[6] = g;
        array[7] = h;
        array[8] = i;
        array[9] = j;
    }

    function _arr(
        uint256[] memory a,
        uint256[] memory b
    ) internal pure returns (uint256[][] memory array) {
        array = new uint256[][](2);
        array[0] = a;
        array[1] = b;
    }

    function _arr(
        uint256[] memory a,
        uint256[] memory b,
        uint256[] memory c
    ) internal pure returns (uint256[][] memory array) {
        array = new uint256[][](3);
        array[0] = a;
        array[1] = b;
        array[2] = c;
    }

    function _arr(
        uint256[] memory a,
        uint256[] memory b,
        uint256[] memory c,
        uint256[] memory d
    ) internal pure returns (uint256[][] memory array) {
        array = new uint256[][](4);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
    }

    function _arr(
        uint256[] memory a,
        uint256[] memory b,
        uint256[] memory c,
        uint256[] memory d,
        uint256[] memory e
    ) internal pure returns (uint256[][] memory array) {
        array = new uint256[][](5);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
        array[4] = e;
    }

    function _arr(
        uint256[] memory a,
        uint256[] memory b,
        uint256[] memory c,
        uint256[] memory d,
        uint256[] memory e,
        uint256[] memory f
    ) internal pure returns (uint256[][] memory array) {
        array = new uint256[][](6);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
        array[4] = e;
        array[5] = f;
    }

    function _arr(
        uint256[] memory a,
        uint256[] memory b,
        uint256[] memory c,
        uint256[] memory d,
        uint256[] memory e,
        uint256[] memory f,
        uint256[] memory g
    ) internal pure returns (uint256[][] memory array) {
        array = new uint256[][](7);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
        array[4] = e;
        array[5] = f;
        array[6] = g;
    }

    function _arr(
        uint256[] memory a,
        uint256[] memory b,
        uint256[] memory c,
        uint256[] memory d,
        uint256[] memory e,
        uint256[] memory f,
        uint256[] memory g,
        uint256[] memory h
    ) internal pure returns (uint256[][] memory array) {
        array = new uint256[][](8);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
        array[4] = e;
        array[5] = f;
        array[6] = g;
        array[7] = h;
    }

    function _arr(
        uint256[] memory a,
        uint256[] memory b,
        uint256[] memory c,
        uint256[] memory d,
        uint256[] memory e,
        uint256[] memory f,
        uint256[] memory g,
        uint256[] memory h,
        uint256[] memory i
    ) internal pure returns (uint256[][] memory array) {
        array = new uint256[][](9);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
        array[4] = e;
        array[5] = f;
        array[6] = g;
        array[7] = h;
        array[8] = i;
    }

    function _arr(
        uint256[] memory a,
        uint256[] memory b,
        uint256[] memory c,
        uint256[] memory d,
        uint256[] memory e,
        uint256[] memory f,
        uint256[] memory g,
        uint256[] memory h,
        uint256[] memory i,
        uint256[] memory j
    ) internal pure returns (uint256[][] memory array) {
        array = new uint256[][](10);
        array[0] = a;
        array[1] = b;
        array[2] = c;
        array[3] = d;
        array[4] = e;
        array[5] = f;
        array[6] = g;
        array[7] = h;
        array[8] = i;
        array[9] = j;
    }
}
