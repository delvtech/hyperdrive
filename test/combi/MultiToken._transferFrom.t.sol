// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { BaseTest, TestLib as Lib } from "test/Test.sol";
import { MockMultiToken } from "test/mocks/MockMultiToken.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";

contract MultiToken__transferFrom is BaseTest {
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

    function testCombinatorial__MultiToken__transferFrom() public {
        uint256[][] memory inputs = new uint256[][](4);

        // amount
        inputs[0] = new uint256[](5);
        inputs[0][0] = 0;
        inputs[0][1] = 1;
        inputs[0][2] = 1e18;
        inputs[0][3] = 1000000e18;
        inputs[0][4] = type(uint256).max;

        // caller
        inputs[1] = new uint256[](2);
        inputs[1][0] = 0;
        inputs[1][1] = 1;

        // approvals
        inputs[2] = new uint256[](4);
        inputs[2][0] = 0;
        inputs[2][1] = 10e18;
        inputs[2][2] = type(uint128).max; // use this for approvedForAll
        inputs[2][3] = type(uint256).max;

        // balanceOf(from/to)
        inputs[3] = new uint256[](3);
        inputs[3][0] = 0;
        inputs[3][1] = 100e18;
        inputs[3][2] = (2 ** 96) + 98237.12111e5;

        uint256[][] memory rawTestCases = Lib.matrix(inputs);

        for (uint256 i = 0; i < rawTestCases.length; i++) {
            require(
                rawTestCases[i].length == 4,
                "Raw test case must have length of 4"
            );

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

            __setup(testCase);
            if (__fail(testCase)) {
                __success(testCase);
            }
        }

        console2.log(
            "###- %s test cases passed for MultiToken._transferFrom() -###",
            rawTestCases.length
        );
    }

    function __setup(TestCase_transferFrom memory testCase) internal {
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
    ) internal returns (bool isSuccessCase) {
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
                __log("EXPECTED FAIL", testCase);
                revert("SHOULD NOT SUCCEED!");
            } catch (bytes memory __error) {
                if (Lib.neq(__error, stdError.arithmeticError)) {
                    __log("CASE FAIL", testCase);
                    assertEq(__error, stdError.arithmeticError);
                }
                return false;
            }
        }
        return true;
    }

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    function __success(TestCase_transferFrom memory testCase) internal {
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(
            testCase.caller,
            testCase.from,
            testCase.to,
            testCase.tokenId,
            testCase.amount
        );

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

        try
            multiToken.__external_transferFrom(
                testCase.tokenId,
                testCase.from,
                testCase.to,
                testCase.amount,
                testCase.caller
            )
        {} catch {
            __log("EXPECTED SUCCEED", testCase);
            revert("SHOULD NOT FAIL!");
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
                __log("", testCase);
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
            __log("", testCase);
            assertEq(
                fromBalanceDiff,
                testCase.amount,
                "from account balance must have decreased by amount"
            );
        }

        if (toBalanceDiff != testCase.amount) {
            __log("", testCase);
            assertEq(
                toBalanceDiff,
                testCase.amount,
                "to account balance must have increased by amount"
            );
        }
    }

    function __log(
        string memory prelude,
        TestCase_transferFrom memory testCase
    ) internal view {
        console2.log("%s :: ", prelude);
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
