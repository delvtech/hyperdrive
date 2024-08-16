// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { ERC20ForwarderFactory } from "../../contracts/src/token/ERC20ForwarderFactory.sol";
import { IMockHyperdrive } from "../../contracts/test/MockHyperdrive.sol";
import { CombinatorialTest } from "../utils/CombinatorialTest.sol";

contract MultiToken__transferFrom is CombinatorialTest {
    struct TestCase {
        uint256 index;
        // -- args
        uint256 tokenId;
        address from;
        address to;
        uint256 amount;
        address caller;
        // -- context
        uint256 approvals;
        uint256 balanceFrom;
        uint256 balanceTo;
        bool approvedForAll;
    }

    function test__MultiToken__transferFrom() public {
        // Construction of combinatorial matrix
        uint256[][] memory rawTestCases = __matrix(
            _arr(
                // amount
                _arr(0, 1, 1e18, 1000000e18, type(uint256).max),
                // caller
                _arr(0, 1),
                // approvals
                _arr(0, 10e18, type(uint128).max, type(uint256).max),
                // balanceOf(from/to)
                _arr(0, 100e18, (2 ** 96) + 98237.12111e5)
            )
        );

        // Iterate through every test case combination and check if they __fail/__success
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            uint256 approvals = rawTestCases[i][2];
            bool approvedForAll = approvals == type(uint128).max;
            TestCase memory testCase = TestCase({
                index: i,
                tokenId: ((i + 5) ** 4) / 7,
                from: alice,
                to: bob,
                amount: rawTestCases[i][0],
                caller: rawTestCases[i][1] > 0 ? alice : celine,
                approvals: approvals,
                balanceFrom: rawTestCases[i][3],
                balanceTo: rawTestCases[i][3],
                approvedForAll: approvedForAll
            });
            __setup(testCase);
            __fail(testCase);
            __success(testCase);
        }

        console2.log(
            "###- %s test cases passed for MultiToken._transferFrom() -###",
            rawTestCases.length
        );
    }

    function __setup(TestCase memory testCase) internal __combinatorial_setup {
        // Set balances of the "from" and "to" addresses
        IMockHyperdrive(address(hyperdrive)).__setBalanceOf(
            testCase.tokenId,
            testCase.from,
            testCase.balanceFrom
        );
        IMockHyperdrive(address(hyperdrive)).__setBalanceOf(
            testCase.tokenId,
            testCase.to,
            testCase.balanceTo
        );

        // When the "caller" is not "from", then an approved transfer is the
        // intention and so approvals must be made by "from" for "caller"
        if (testCase.caller != testCase.from) {
            vm.startPrank(testCase.from);
            if (testCase.approvedForAll) {
                hyperdrive.setApprovalForAll(testCase.caller, true);
            } else {
                hyperdrive.setApprovalForAll(testCase.caller, false);
                hyperdrive.setApproval(
                    testCase.tokenId,
                    testCase.caller,
                    testCase.approvals
                );
            }
            vm.stopPrank();
        }
    }

    function __fail(TestCase memory testCase) internal __combinatorial_fail {
        // Approval underflows occur when the following conditions are met
        // - "caller" is not "from"
        // - isApprovedForAll[from][caller] is not true
        // - "approvals" is non-infinite (max uint256)
        // - "amount" to transfer is greater than "approvals"
        bool approvalUnderflows = testCase.caller != testCase.from &&
            !testCase.approvedForAll &&
            testCase.approvals != type(uint256).max &&
            testCase.approvals < testCase.amount;

        // Underflow occurs when the "from" balance is less than "amount"
        bool balanceFromUnderflows = testCase.balanceFrom < testCase.amount;

        // Balance overflows when the "to" balance + "amount" is greater than
        // max uint256
        bool balanceToOverflows = (type(uint256).max - testCase.balanceTo) <
            testCase.amount;

        // If the failure conditions are met then attempt a failing
        // _transferFrom. If the call succeeds then code execution should revert
        if (approvalUnderflows || balanceFromUnderflows || balanceToOverflows) {
            try
                IMockHyperdrive(address(hyperdrive)).__external_transferFrom(
                    testCase.tokenId,
                    testCase.from,
                    testCase.to,
                    testCase.amount,
                    testCase.caller
                )
            {
                __log(unicode"❎", testCase);
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
        // Fetch "from" and "to" balances prior to function under testing being
        // executed to perform differential checking
        uint256 preBalanceFrom = hyperdrive.balanceOf(
            testCase.tokenId,
            testCase.from
        );
        uint256 preBalanceTo = hyperdrive.balanceOf(
            testCase.tokenId,
            testCase.to
        );
        // Fetch "from's" approvals for "caller" prior to function under testing
        // being executed to perform differential checking in the case of
        // non-infinite approvals being set
        uint256 preCallerApprovals = hyperdrive.perTokenApprovals(
            testCase.tokenId,
            testCase.from,
            testCase.caller
        );

        // Register the TransferSingle event
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(
            testCase.caller,
            testCase.from,
            testCase.to,
            testCase.tokenId,
            testCase.amount
        );

        // Execute the function under test. It is expected to succeed and any
        // failure will cause the code execution to revert
        try
            IMockHyperdrive(address(hyperdrive)).__external_transferFrom(
                testCase.tokenId,
                testCase.from,
                testCase.to,
                testCase.amount,
                testCase.caller
            )
        {} catch {
            __log(unicode"❎", testCase);
            revert ExpectedSuccess();
        }

        // When a non-infinite approval is set, validate that the difference
        // of the before and after perTokenApprovals of the "caller" is equal
        // to "amount"
        if (
            testCase.caller != testCase.from &&
            !testCase.approvedForAll &&
            testCase.approvals != type(uint256).max
        ) {
            uint256 callerApprovalsDiff = preCallerApprovals -
                hyperdrive.perTokenApprovals(
                    testCase.tokenId,
                    testCase.from,
                    testCase.caller
                );

            if (callerApprovalsDiff != testCase.amount) {
                __log(unicode"❎", testCase);
                assertEq(
                    callerApprovalsDiff,
                    testCase.amount,
                    "number of approvals must have decreased by amount"
                );
            }
        }

        // Difference of before and after "from" balances should be "amount"
        uint256 fromBalanceDiff = preBalanceFrom -
            hyperdrive.balanceOf(testCase.tokenId, testCase.from);
        if (fromBalanceDiff != testCase.amount) {
            __log(unicode"❎", testCase);
            assertEq(
                fromBalanceDiff,
                testCase.amount,
                "from account balance must have decreased by amount"
            );
        }

        // Difference of before and after "to" balances should be "amount"
        uint256 toBalanceDiff = hyperdrive.balanceOf(
            testCase.tokenId,
            testCase.to
        ) - preBalanceTo;
        if (toBalanceDiff != testCase.amount) {
            __log(unicode"❎", testCase);
            assertEq(
                toBalanceDiff,
                testCase.amount,
                "to account balance must have increased by amount"
            );
        }
    }

    function __log(
        string memory prelude,
        TestCase memory testCase
    ) internal pure {
        console2.log("");
        console2.log("%s Fail :: { TestCase #%s }\n", prelude, testCase.index);
        console2.log("\ttokenId           = ", testCase.tokenId);
        console2.log("\tfrom              = ", testCase.from);
        console2.log("\tto                = ", testCase.to);
        console2.log("\tamount            = ", testCase.amount);
        console2.log("\tcaller            = ", testCase.caller);
        console2.log("\tapprovals         = ", testCase.approvals);
        console2.log("\tbalanceFrom       = ", testCase.balanceFrom);
        console2.log("\tbalanceTo         = ", testCase.balanceTo);
        console2.log("\tapprovedForAll    = ", testCase.approvedForAll);
        console2.log("");
    }
}
