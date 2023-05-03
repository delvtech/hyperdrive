// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { CombinatorialTest } from "test/utils/CombinatorialTest.sol";
import { MockMultiToken } from "contracts/test/MockMultiToken.sol";
import { MockBondWrapper } from "contracts/test/MockBondWrapper.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";

contract BondWrapper_mint is CombinatorialTest {
    MockMultiToken multiToken;
    MockBondWrapper bondWrapper;
    ERC20Mintable baseToken;

    function setUp() public override {
        super.setUp();
        vm.startPrank(deployer);

        // FIXME: Use a real data provider.
        multiToken = new MockMultiToken(
            address(0),
            bytes32(0),
            address(forwarderFactory)
        );
        baseToken = new ERC20Mintable();
    }

    struct TestCase {
        uint256 index;
        // -- args
        uint256 maturityTime;
        uint256 amount;
        address destination;
        // -- context
        uint256 blockTimestamp;
        uint256 unwrappedBonds;
        uint256 mintPercent;
        address user;
        // -- other
        uint256 assetId;
    }

    function test__BondWrapper_mint() public {
        // Construction of combinatorial matrix
        uint256[][] memory rawTestCases = __matrix(
            _arr(
                // maturityTime
                _arr(0, 1 hours, 10 days, 365 days),
                // amount
                _arr(0, 1, 1e18, 999212e18, 77776766e18 + 28, 7777676612319e52),
                // destination
                _arr(0, 1, 2),
                // blockTimestamp
                _arr(0, 2 hours, 9 days, 444 days),
                // unwrappedBonds
                _arr(0, 1e18, 1e27 + 12879187, type(uint256).max),
                // mintPercent
                _arr(0, 1, 0.05e18, 25e18),
                // user
                _arr(0, 1, 2)
            )
        );

        // Iterate through every test case combination and check if they __fail/__success
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            address destination = rawTestCases[i][2] == 0
                ? alice
                : rawTestCases[i][2] == 1
                ? bob
                : celine;
            address user = rawTestCases[i][6] == 0
                ? alice
                : rawTestCases[i][6] == 1
                ? dan
                : eve;
            // We use offsets for time context
            uint256 maturityTime = __init__ + rawTestCases[i][0];
            uint256 blockTimestamp = __init__ + rawTestCases[i][3];

            // Encoding the assetId as it's easier to reference
            uint256 assetId = AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Long,
                maturityTime
            );

            TestCase memory testCase = TestCase({
                index: i,
                maturityTime: maturityTime,
                amount: rawTestCases[i][1],
                destination: destination,
                blockTimestamp: blockTimestamp,
                unwrappedBonds: rawTestCases[i][4],
                mintPercent: rawTestCases[i][5],
                user: user,
                assetId: assetId
            });
            __setup(testCase);
            __fail(testCase);
            __success(testCase);
        }

        console2.log(
            "###- %s test cases passed for BondWrapper.mint() -###",
            rawTestCases.length
        );
    }

    function __setup(TestCase memory testCase) internal __combinatorial_setup {
        // Deploy contract with a new mint percent
        bondWrapper = new MockBondWrapper(
            IHyperdrive(address(multiToken)),
            IERC20(address(baseToken)),
            testCase.mintPercent,
            "Bond",
            "BND"
        );

        // Set timestamp
        vm.warp(testCase.blockTimestamp);

        // Set balance of unwrapped bonds
        multiToken.__setBalanceOf(
            testCase.assetId,
            testCase.user,
            testCase.unwrappedBonds
        );

        // Ensure that the bondWrapper contract has been approved by the user
        vm.stopPrank();
        vm.startPrank(testCase.user);
        multiToken.setApprovalForAll(address(bondWrapper), true);
    }

    function __fail(TestCase memory testCase) internal __combinatorial_fail {
        // bond must not have matured
        bool bondHasMatured = testCase.maturityTime <= testCase.blockTimestamp;

        // Can not transfer an amount of bonds which don't exist
        bool notEnoughBonds = testCase.unwrappedBonds < testCase.amount;

        // Ludicrous overflow case when amount * mintPercent > 2^256
        bool mintAmountOverflow = testCase.mintPercent == 0
            ? false
            : type(uint256).max / testCase.mintPercent < testCase.amount;

        if (bondHasMatured) {
            __fail_error = abi.encodeWithSelector(Errors.BondMatured.selector);
        } else if (notEnoughBonds || mintAmountOverflow) {
            __fail_error = stdError.arithmeticError;
        }

        if (bondHasMatured || notEnoughBonds || mintAmountOverflow) {
            try
                bondWrapper.mint(
                    testCase.maturityTime,
                    testCase.amount,
                    testCase.destination
                )
            {
                __log(unicode"❎", testCase);
                revert ExpectedFail();
            } catch (bytes memory e) {
                // NOTE: __error and __fail_error must be assigned here to
                // validate failure reason
                __error = e;
            }
        }
    }

    function __success(
        TestCase memory testCase
    ) internal __combinatorial_success {
        uint256 userUnwrappedBondBalance = multiToken.balanceOf(
            testCase.assetId,
            testCase.user
        );
        uint256 bondWrapperUnwrappedBondBalance = multiToken.balanceOf(
            testCase.assetId,
            address(bondWrapper)
        );

        uint256 destinationBondBalance = bondWrapper.balanceOf(
            testCase.destination
        );

        uint256 destinationDeposits = bondWrapper.deposits(
            testCase.destination,
            testCase.assetId
        );

        try
            bondWrapper.mint(
                testCase.maturityTime,
                testCase.amount,
                testCase.destination
            )
        {} catch {
            __log(unicode"❎", testCase);
            revert ExpectedSuccess();
        }

        uint256 userUnwrappedBondBalanceDiff = userUnwrappedBondBalance -
            multiToken.balanceOf(testCase.assetId, testCase.user);
        if (userUnwrappedBondBalanceDiff != testCase.amount) {
            __log(unicode"❎", testCase);
            assertEq(
                userUnwrappedBondBalanceDiff,
                testCase.amount,
                "expect user to have less multitoken bonds"
            );
        }

        uint256 bondWrapperUnwrappedBondBalanceDiff = multiToken.balanceOf(
            testCase.assetId,
            address(bondWrapper)
        ) - bondWrapperUnwrappedBondBalance;
        if (bondWrapperUnwrappedBondBalanceDiff != testCase.amount) {
            __log(unicode"❎", testCase);
            assertEq(
                bondWrapperUnwrappedBondBalanceDiff,
                testCase.amount,
                "expect bond wrapper contract to have more multitoken bonds"
            );
        }

        uint256 destinationBondBalanceDiff = bondWrapper.balanceOf(
            testCase.destination
        ) - destinationBondBalance;
        if (
            destinationBondBalanceDiff !=
            ((testCase.amount * testCase.mintPercent) / 10000)
        ) {
            __log(unicode"❎", testCase);
            assertEq(
                destinationBondBalanceDiff,
                testCase.amount,
                "expect destination to have minted some bond wrapper tokens"
            );
        }

        uint256 destinationDepositDiff = bondWrapper.deposits(
            testCase.destination,
            testCase.assetId
        ) - destinationDeposits;

        if (destinationDepositDiff != testCase.amount) {
            __log(unicode"❎", testCase);
            assertEq(
                destinationDepositDiff,
                testCase.amount,
                "expect user deposits to have been tracked"
            );
        }
    }

    function __log(
        string memory prelude,
        TestCase memory testCase
    ) internal view {
        console2.log("");
        console2.log("%s Fail :: { TestCase #%s }\n", prelude, testCase.index);
        console2.log("\tmaturityTime           = ", testCase.maturityTime);
        console2.log("\tamount                 = ", testCase.amount);
        console2.log("\tdestination            = ", testCase.destination);
        console2.log("\tblockTimestamp         = ", testCase.blockTimestamp);
        console2.log("\tunwrappedBonds         = ", testCase.unwrappedBonds);
        console2.log("\tmintPercent            = ", testCase.mintPercent);
        console2.log("\tuser                   = ", testCase.user);
        console2.log("");
    }
}
