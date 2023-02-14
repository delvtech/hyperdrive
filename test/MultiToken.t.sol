// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { BaseTest, TestLib as Lib } from "test/Test.sol";
import { MultiToken } from "contracts/MultiToken.sol";

import { ForwarderFactory } from "contracts/ForwarderFactory.sol";

import "forge-std/console2.sol";

contract MockMultiToken is MultiToken {
    constructor(
        bytes32 _linkerCodeHash,
        address _factory
    ) MultiToken(_linkerCodeHash, _factory) {}

    function setNameAndSymbol(
        uint256 tokenId,
        string memory __name,
        string memory __symbol
    ) external {
        _name[tokenId] = __name;
        _symbol[tokenId] = __symbol;
    }

    // function mint(uint256 _tokenID, address _to, uint256 _amount) external {
    //     _mint(_tokenID, _to, _amount);
    // }

    // function burn(uint256 _tokenID, address _from, uint256 _amount) external {
    //     _burn(_tokenID, _from, _amount);
    // }

    function setBalanceOf(
        uint256 _tokenId,
        address _who,
        uint256 _amount
    ) external {
        console2.log("jbjbjbqqq");
        uint256 balance = balanceOf[_tokenId][_who];
        if (balance > 0) {
            _burn(_tokenId, _who, balance);
        }
        _mint(_tokenId, _who, _amount);
    }
}

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

    // ------------------- transferFrom ------------------- //

    function test__combinatorial_transferFrom() public {
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
        inputs[2] = new uint256[](3);
        inputs[2][0] = 0;
        inputs[2][1] = 10e18;
        inputs[2][2] = type(uint256).max;

        // mintAmount
        inputs[3] = new uint256[](2);
        inputs[3][0] = 0;
        inputs[3][1] = type(uint96).max;

        __combinatorial_transferFrom_run(
            __combinatorial_transferFrom_convert(Lib.matrix(inputs))
        );
    }

    struct TransferFromTestCase {
        // -- args
        uint256 tokenId;
        address from;
        address to;
        uint256 amount;
        // -- context
        bool isDirectTransfer;
        uint256 allowance;
        uint256 mintAmount;
        bool approvedForAll;
    }

    function __combinatorial_transferFrom_convert(
        uint256[][] memory rawTestCases
    ) internal view returns (TransferFromTestCase[] memory testCases) {
        testCases = new TransferFromTestCase[](rawTestCases.length);
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            require(
                rawTestCases[i].length == 4,
                "Raw test case must have length of 4"
            );
            bool isDirectTransfer = rawTestCases[i][1] > 0;
            uint256 allowance = rawTestCases[i][2];
            bool approvedForAll = !isDirectTransfer &&
                allowance == type(uint256).max &&
                (i % 2 == 1);

            testCases[i] = TransferFromTestCase({
                tokenId: ((i + 5) ** 4) / 7,
                from: alice,
                to: bob,
                amount: rawTestCases[i][0],
                isDirectTransfer: isDirectTransfer,
                allowance: allowance,
                mintAmount: rawTestCases[i][3],
                approvedForAll: approvedForAll
            });
        }
    }

    function __combinatorial_transferFrom_run(
        TransferFromTestCase[] memory testCases
    ) internal {
        console2.log("jbjbj");

        for (uint256 i = 0; i < testCases.length; i++) {
            __combinatorial_transferFrom_log("EXPECTED FAIL", testCases[i]);
            // ### SETUP ###
            __combinatorial_transferFrom_setup(testCases[i]);
            // ### ERROR ###
            (
                bool _is_error,
                bytes memory _error
            ) = __combinatorial_transferFrom_fail(testCases[i]);

            if (_is_error) {
                // ### FAIL CASE ###
                try
                    multiToken.transferFrom(
                        testCases[i].tokenId,
                        testCases[i].from,
                        testCases[i].to,
                        testCases[i].amount
                    )
                {
                    __combinatorial_transferFrom_log(
                        "EXPECTED FAIL",
                        testCases[i]
                    );
                    revert("SHOULD NOT SUCCEED!");
                } catch (bytes memory __error) {
                    if (Lib.neq(__error, _error)) {
                        __combinatorial_transferFrom_log(
                            "CASE FAIL",
                            testCases[i]
                        );
                        assertEq(__error, _error);
                    }
                }
            } else {
                // ### SUCCESS CASE ###
                try
                    multiToken.transferFrom(
                        testCases[i].tokenId,
                        testCases[i].from,
                        testCases[i].to,
                        testCases[i].amount
                    )
                {
                    __combinatorial_transferFrom_success(testCases[i]);
                } catch {
                    __combinatorial_transferFrom_log(
                        "EXPECTED SUCCEED",
                        testCases[i]
                    );
                    revert("SHOULD NOT FAIL!");
                }
            }
            vm.stopPrank();
        }
    }

    function __combinatorial_transferFrom_setup(
        TransferFromTestCase memory testCase
    ) internal {
        console2.log("testCase.tokenId: %s", testCase.tokenId);
        console2.log("alice: %s", alice);
        console2.log("testCase.mintAmount: %s", testCase.mintAmount);

        multiToken.setBalanceOf(testCase.tokenId, alice, testCase.mintAmount);

        console2.log("jbjbj");
        if (!testCase.isDirectTransfer) {
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

    function __combinatorial_transferFrom_fail(
        TransferFromTestCase memory testCase
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

    function __combinatorial_transferFrom_success(
        TransferFromTestCase memory testCase
    ) internal {}

    function __combinatorial_transferFrom_log(
        string memory prelude,
        TransferFromTestCase memory testCase
    ) internal view {
        console2.log("%s :: ", prelude);
        console2.log("");
        console2.log("\ttokenId           = ", testCase.tokenId);
        console2.log("\tfrom              = ", testCase.from);
        console2.log("\tto                = ", testCase.to);
        console2.log("\tamount            = ", testCase.amount);
        console2.log("\tisDirectTransfer  = ", testCase.isDirectTransfer);
        console2.log("\tallowance         = ", testCase.allowance);
        console2.log("\tmintAmount        = ", testCase.mintAmount);
        console2.log("\tapprovedForAll    = ", testCase.approvedForAll);
        console2.log("");
    }
}
