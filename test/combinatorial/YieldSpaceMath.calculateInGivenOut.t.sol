// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { CombinatorialTest, TestLib as lib } from "test/Test.sol";
import { YieldSpaceMath } from "contracts/libraries/YieldSpaceMath.sol";

contract YieldSpaceMath_calculateInGivenOut is CombinatorialTest {
    // function setUp() public override {
    //     super.setUp();
    // }

    struct TestCase {
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 bondReserveAdjustment;
        uint256 amountOut;
        uint256 stretchedTimeElapsed;
        uint256 c;
        uint256 mu;
        bool isBondIn;
    }

    function test__YieldSpaceMath_calculateInGivenOut() public {
        // Construction of combinatorial matrix
        uint256[][] memory rawTestCases = lib.matrix(
            lib._arr(lib._arr(), lib._arr(), lib._arr(), lib._arr())
        );

        // Iterate through every test case combination and check if they __fail/__success
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            uint256 approvals = rawTestCases[i][2];
            bool approvedForAll = approvals == type(uint128).max;
            TestCase memory testCase = TestCase();
            __log("--", i, testCase);
            __setup(testCase);
            __fail(testCase);
            __success(testCase);
        }

        console2.log(
            "###- %s test cases passed for MultiToken._transferFrom() -###",
            rawTestCases.length
        );
    }

    function __setup(TestCase memory testCase) internal __combinatorial_setup {}

    function __fail(TestCase memory testCase) internal __combinatorial_fail {
        // If the failure conditions are met then attempt a failing
        // _transferFrom. If the call succeeds then code execution should revert
        if (false) {
            try
                YieldSpaceMath.calculateInGivenOut(
                    testCase.shareReserves,
                    testCase.bondReserves,
                    testCase.bondReserveAdjustment,
                    testCase.amountOut,
                    testCase.stretchedTimeElapsed,
                    testCase.c,
                    testCase.mu,
                    testCase.isBondIn
                )
            {
                revert ExpectedFail();
            } catch (bytes memory e) {
                // NOTE: __error and __fail_error must be assigned here to
                // validate failure reason
                __error = e;
                __fail_error = stdError.arithmeticError;
            }
        }
    }

    function __success(
        TestCase memory testCase
    ) internal __combinatorial_success {
        try
            YieldSpaceMath.calculateInGivenOut(
                testCase.shareReserves,
                testCase.bondReserves,
                testCase.bondReserveAdjustment,
                testCase.amountOut,
                testCase.stretchedTimeElapsed,
                testCase.c,
                testCase.mu,
                testCase.isBondIn
            )
        {} catch {
            revert ExpectedSuccess();
        }
    }

    function __log(
        string memory prelude,
        uint256 index,
        TestCase memory testCase
    ) internal view {
        console2.log("%s :: { TestCase #%s }", prelude, index);
        console2.log("");
        console2.log("\tshareReserves             = ", testCase.shareReserves);
        console2.log("\tbondReserves              = ", testCase.bondReserves);
        console2.log(
            "\tbondReserveAdjustment     = ",
            testCase.bondReserveAdjustment
        );
        console2.log("\tamountOut                 = ", testCase.amountOut);
        console2.log(
            "\tstretchedTimeElapsed      = ",
            testCase.stretchedTimeElapsed
        );
        console2.log("\tc                         = ", testCase.c);
        console2.log("\tmu                        = ", testCase.mu);
        console2.log("\tisBondIn                  = ", testCase.isBondIn);
        console2.log("");
    }
}
