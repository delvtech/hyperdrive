// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { CombinatorialTest, TestLib as lib } from "test/Test.sol";
import { MockMultiToken } from "test/mocks/MockMultiToken.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";

contract MultiToken__transferFrom is CombinatorialTest {
    ForwarderFactory forwarderFactory;
    MockMultiToken multiToken;

    function setUp() public override {
        super.setUp();
        vm.startPrank(deployer);
        forwarderFactory = new ForwarderFactory();
        multiToken = new MockMultiToken(bytes32(0), address(forwarderFactory));
        vm.stopPrank();
    }

    struct TestCase_transferFrom {
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

    function test_Combinatorial__MultiToken__transferFrom() public {
        uint256[][] memory rawTestCases = lib.matrix(
            lib._arr(
                // amount
                lib._arr(0, 1, 1e18, 1000000e18, type(uint256).max),
                // caller
                lib._arr(0, 1),
                // approvals
                lib._arr(0, 10e18, type(uint128).max, type(uint256).max),
                // balanceOf(from/to)
                lib._arr(0, 100e18, (2 ** 96) + 98237.12111e5)
            )
        );

        for (uint256 i = 0; i < rawTestCases.length; i++) {
            uint256 approvals = rawTestCases[i][2];
            bool approvedForAll = approvals == type(uint128).max;

            TestCase_transferFrom memory testCase = TestCase_transferFrom({
                tokenId: ((i + 5) ** 4) / 7,
                from: alice,
                to: bob,
                amount: rawTestCases[i][0],
                caller: rawTestCases[i][1] > 0 ? alice : eve,
                approvals: approvals,
                balanceFrom: rawTestCases[i][3],
                balanceTo: rawTestCases[i][3],
                approvedForAll: approvedForAll
            });

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

    function __setup(
        TestCase_transferFrom memory testCase
    ) internal __combinatorial_setup {
        multiToken.__setBalanceOf(
            testCase.tokenId,
            testCase.from,
            testCase.balanceFrom
        );
        multiToken.__setBalanceOf(
            testCase.tokenId,
            testCase.to,
            testCase.balanceTo
        );
        if (testCase.caller != testCase.from) {
            // If the caller is not from, from must set an approvals for caller
            vm.startPrank(testCase.from);
            if (testCase.approvedForAll) {
                multiToken.setApprovalForAll(testCase.caller, true);
            } else {
                multiToken.setApprovalForAll(testCase.caller, false);
                multiToken.setApproval(
                    testCase.tokenId,
                    testCase.caller,
                    testCase.approvals
                );
            }
            vm.stopPrank();
        }
    }

    function __fail(
        TestCase_transferFrom memory testCase
    ) internal __combinatorial_fail {
        bool approvalUnderflows = testCase.caller != testCase.from &&
            !testCase.approvedForAll &&
            testCase.approvals != type(uint256).max &&
            testCase.approvals < testCase.amount;

        bool balanceFromUnderflows = testCase.balanceFrom < testCase.amount;

        bool balanceToOverflows = (type(uint256).max - testCase.balanceTo) <
            testCase.amount;

        if (approvalUnderflows || balanceFromUnderflows || balanceToOverflows) {
            try
                multiToken.__external_transferFrom(
                    testCase.tokenId,
                    testCase.from,
                    testCase.to,
                    testCase.amount,
                    testCase.caller
                )
            {
                revert("EXPECTED FAIL");
            } catch (bytes memory e) {
                __error = e;
                __fail_error = stdError.arithmeticError;
            }
        }
    }

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    function __success(
        TestCase_transferFrom memory testCase
    ) internal __combinatorial_success {
        uint256 preBalanceFrom = multiToken.balanceOf(
            testCase.tokenId,
            testCase.from
        );
        uint256 preBalanceTo = multiToken.balanceOf(
            testCase.tokenId,
            testCase.to
        );
        uint256 preCallerApprovals = multiToken.perTokenApprovals(
            testCase.tokenId,
            testCase.from,
            testCase.caller
        );

        // _transferFrom emits the TransferSingle event in success cases
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(
            testCase.caller,
            testCase.from,
            testCase.to,
            testCase.tokenId,
            testCase.amount
        );

        try
            multiToken.__external_transferFrom(
                testCase.tokenId,
                testCase.from,
                testCase.to,
                testCase.amount,
                testCase.caller
            )
        {} catch {
            revert("EXPECTED SUCCESS");
        }
        if (
            testCase.caller != testCase.from &&
            !testCase.approvedForAll &&
            testCase.approvals != type(uint256).max
        ) {
            uint256 callerApprovalsDiff = preCallerApprovals -
                multiToken.perTokenApprovals(
                    testCase.tokenId,
                    testCase.from,
                    testCase.caller
                );

            if (callerApprovalsDiff != testCase.amount) {
                assertEq(
                    callerApprovalsDiff,
                    testCase.amount,
                    "number of approvals must have decreased by amount"
                );
            }
        }

        uint256 fromBalanceDiff = preBalanceFrom -
            multiToken.balanceOf(testCase.tokenId, testCase.from);

        uint256 toBalanceDiff = multiToken.balanceOf(
            testCase.tokenId,
            testCase.to
        ) - preBalanceTo;

        if (fromBalanceDiff != testCase.amount) {
            assertEq(
                fromBalanceDiff,
                testCase.amount,
                "from account balance must have decreased by amount"
            );
        }

        if (toBalanceDiff != testCase.amount) {
            assertEq(
                toBalanceDiff,
                testCase.amount,
                "to account balance must have increased by amount"
            );
        }
    }

    function __log(
        string memory prelude,
        uint256 index,
        TestCase_transferFrom memory testCase
    ) internal view {
        console2.log("%s :: { TestCase #%s }", prelude, index);
        console2.log("");
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
