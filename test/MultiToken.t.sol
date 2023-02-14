// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { BaseTest, TestLib as Lib } from "test/Test.sol";
import { MockMultiToken } from "test/mocks/MockMultiToken.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";

import "forge-std/console2.sol";

contract MultiTokenTest is BaseTest {
    ForwarderFactory forwarderFactory;
    MockMultiToken multiToken;

    function setUp() public override {
        super.setUp();
        forwarderFactory = new ForwarderFactory();
    }

    // ------------------- simple tests ------------------- //

    function test__name_symbol() public {
        vm.startPrank(deployer);
        multiToken = new MockMultiToken(bytes32(0), address(forwarderFactory));
        multiToken.setNameAndSymbol(5, "Token", "TKN");

        vm.stopPrank();
        assertEq(multiToken.name(5), "Token");
        assertEq(multiToken.symbol(5), "TKN");
    }

    // ------------------- _transferFrom ------------------- //

    function test__combi_transferFrom() public {
        uint256[][] memory inputs = new uint256[][](4);

        // amount
        inputs[0] = new uint256[](4);
        inputs[0][0] = 0;
        inputs[0][1] = 1;
        inputs[0][2] = 1e18;
        inputs[0][3] = 1000000e18;

        // isDirectTransfer
        inputs[1] = new uint256[](2);
        inputs[1][0] = 0;
        inputs[1][1] = 1;

        // allowance
        inputs[2] = new uint256[](4);
        inputs[2][0] = 0;
        inputs[2][1] = 10e18;
        inputs[2][2] = type(uint128).max; // use this for approvedForAll
        inputs[2][3] = type(uint256).max;

        // mintAmount
        inputs[3] = new uint256[](2);
        inputs[3][0] = 0;
        inputs[3][1] = type(uint96).max;

        __run(__convert(Lib.matrix(inputs)));
    }

    struct TestCase_transferFrom {
        // -- args
        uint256 tokenId;
        address from;
        address to;
        uint256 amount;
        address caller;
        // -- context
        uint256 allowance;
        uint256 mintAmount;
        bool approvedForAll;
    }

    function __convert(
        uint256[][] memory rawTestCases
    ) internal view returns (TestCase_transferFrom[] memory testCases) {
        testCases = new TestCase_transferFrom[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            require(
                rawTestCases[i].length == 4,
                "Raw test case must have length of 4"
            );

            uint256 allowance = rawTestCases[i][2];
            bool approvedForAll = allowance == type(uint128).max;

            testCases[i] = TestCase_transferFrom({
                tokenId: ((i + 5) ** 4) / 7,
                from: alice,
                to: bob,
                amount: rawTestCases[i][0],
                caller: rawTestCases[i][1] > 0 ? alice : eve,
                allowance: allowance,
                mintAmount: rawTestCases[i][3],
                approvedForAll: approvedForAll
            });
        }
    }

    function __run(TestCase_transferFrom[] memory testCases) internal {
        for (uint256 i = 0; i < testCases.length; i++) {
            // ### SETUP ###
            __setup(testCases[i]);
            // ### ERROR ###
            (bool _is_error, bytes memory _error) = __check_fail(testCases[i]);
            if (_is_error) {
                // ### FAIL CASE ###
                try
                    multiToken.__external_transferFrom(
                        testCases[i].tokenId,
                        testCases[i].from,
                        testCases[i].to,
                        testCases[i].amount,
                        testCases[i].caller
                    )
                {
                    __log("EXPECTED FAIL", testCases[i]);
                    revert("SHOULD NOT SUCCEED!");
                } catch (bytes memory __error) {
                    if (Lib.neq(__error, _error)) {
                        __log("CASE FAIL", testCases[i]);
                        assertEq(__error, _error);
                    }
                }
            } else {
                // ### SUCCESS CASE ###
                try
                    multiToken.__external_transferFrom(
                        testCases[i].tokenId,
                        testCases[i].from,
                        testCases[i].to,
                        testCases[i].amount,
                        testCases[i].caller
                    )
                {
                    __check_success(testCases[i]);
                } catch {
                    __log("EXPECTED SUCCEED", testCases[i]);
                    revert("SHOULD NOT FAIL!");
                }
            }
            vm.stopPrank();
        }
    }

    function __setup(TestCase_transferFrom memory testCase) internal {
        console2.log("jbjbjj");
        multiToken.setBalanceOf(testCase.tokenId, alice, testCase.mintAmount);
        console2.log("jbjbjj");
        // when eve is the caller we want to alice to
        if (testCase.caller == eve) {
            vm.startPrank(alice);
            if (testCase.approvedForAll) {
                multiToken.setApprovalForAll(eve, true);
            } else {
                multiToken.setApproval(
                    testCase.tokenId,
                    eve,
                    testCase.allowance
                );
            }
            vm.stopPrank();
        }
    }

    function __check_fail(
        TestCase_transferFrom memory testCase
    ) internal pure returns (bool _is_error, bytes memory _error) {
        //if (testCase.isApproved)

        // if (testCase.currentPricePerShare == 0) {
        //     return (true, stdError.divisionError);
        // } else if (
        //     (testCase.interest * _term.one()) / testCase.currentPricePerShare >
        //     testCase.sharesPerExpiry
        // ) {
        //     // TODO: Re-evaluate this case in the context of _releaseYT.
        //     return (true, stdError.arithmeticError);
        // } else if (testCase.totalSupply == 0) {
        //     return (true, stdError.divisionError);
        // } else if (
        //     testCase.amount > testCase.sourceBalance ||
        //     testCase.amount > testCase.totalSupply
        // ) {
        //     return (true, stdError.arithmeticError);
        // }

        return (false, new bytes(0));
    }

    function __check_success(TestCase_transferFrom memory testCase) internal {}

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
        console2.log("\tallowance         = ", testCase.allowance);
        console2.log("\tmintAmount        = ", testCase.mintAmount);
        console2.log("\tapprovedForAll    = ", testCase.approvedForAll);
        console2.log("");
    }
}
