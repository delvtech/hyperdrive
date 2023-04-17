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
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";

contract __MockHyperDrive__ {
    uint256 __closeLongReturnValue__;

    constructor() {}

    event __CloseLong__(
        uint256 indexed _maturityTime,
        uint256 indexed _bondAmount,
        uint256 indexed _minOutput,
        address _destination,
        bool _asUnderlying
    );

    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256) {
        emit __CloseLong__(
            _maturityTime,
            _bondAmount,
            _minOutput,
            _destination,
            _asUnderlying
        );
        return __closeLongReturnValue__;
    }

    function balanceOf(uint256, address) external pure returns (uint256) {
        return 1;
    }

    function __setCloseLongReturnValue__(uint256 _value) external {
        __closeLongReturnValue__ = _value;
    }
}

contract BondWrapper_close is CombinatorialTest {
    using FixedPointMath for uint256;

    __MockHyperDrive__ hyperdrive;
    MockBondWrapper bondWrapper;
    ERC20Mintable baseToken;

    function setUp() public override {
        super.setUp();
        vm.stopPrank();
        vm.startPrank(deployer);

        hyperdrive = new __MockHyperDrive__();
        baseToken = new ERC20Mintable();
    }

    struct TestCase {
        uint256 index;
        // -- args
        uint256 maturityTime;
        uint256 amount;
        bool andBurn;
        address destination;
        // -- context
        uint256 blockTimestamp;
        uint256 receivedAmount;
        uint256 mintPercent;
        address user;
        uint256 userDeposit;
        uint256 userMintAmount;
        uint256 bondWrapperBase;
        // -- other
        uint256 mintedFromBonds;
        uint256 userFunds;
        uint256 assetId;
    }

    function test__BondWrapper_close() public {
        // Construction of combinatorial matrix
        uint256[][] memory rawTestCases = __matrix(
            _arr(
                // maturityTime
                _arr(0, 1 hours, 10 days, 365 days),
                // amount
                _arr(0, 1e18, 999212e18, 77776766e18 + 28, 7777676612319e25),
                // andBurn
                _arr(0, 1),
                // destination
                _arr(0, 1),
                // blockTimestamp
                _arr(0, 2 hours, 9 days, 444 days),
                // mintPercent
                _arr(0, 1, 50, 250, 1000),
                // userDeposit
                _arr(0, 10000000e18, type(uint128).max),
                // userMintAmount
                _arr(0, type(uint128).max),
                // bondWrapperBase
                _arr(0, 1e40 + 2)
            )
        );
        // Iterate through every test case combination and check if they __fail/__success
        for (uint256 i = 0; i < rawTestCases.length; i++) {
            uint256 maturityTime = __init__ + rawTestCases[i][0];
            uint256 amount = rawTestCases[i][1];
            bool andBurn = rawTestCases[i][2] == 1;
            address destination = rawTestCases[i][3] == 0 ? alice : bob;
            uint256 blockTimestamp = __init__ + rawTestCases[i][4];

            uint256 receivedAmount;
            uint256 discount = amount.mulDown(i.mulDown(1e15));
            if (maturityTime > block.timestamp) {
                receivedAmount = discount > amount ? 0 : amount - discount;
            } else {
                receivedAmount = amount;
            }

            address user = alice;

            // Encoding the assetId as it's easier to reference
            uint256 assetId = AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Long,
                maturityTime
            );
            uint256 mintedFromBonds = amount.mulDivDown(
                rawTestCases[i][5],
                10000
            );
            uint256 userFunds = andBurn
                ? receivedAmount
                : receivedAmount < mintedFromBonds
                ? 0
                : (receivedAmount - mintedFromBonds);

            TestCase memory testCase = TestCase({
                index: i,
                maturityTime: maturityTime,
                amount: amount,
                andBurn: andBurn,
                destination: destination,
                blockTimestamp: blockTimestamp,
                receivedAmount: receivedAmount,
                mintPercent: rawTestCases[i][5],
                user: user,
                userDeposit: rawTestCases[i][6],
                userMintAmount: rawTestCases[i][7],
                assetId: assetId,
                mintedFromBonds: mintedFromBonds,
                bondWrapperBase: rawTestCases[i][8],
                userFunds: userFunds
            });
            __setup(testCase);
            __fail(testCase);
            __success(testCase);
        }
        console2.log(
            "###- %s test cases passed for BondWrapper.close() -###",
            rawTestCases.length
        );
    }

    function __setup(TestCase memory testCase) internal __combinatorial_setup {
        // Deploy contract with a new mint percent
        bondWrapper = new MockBondWrapper(
            IHyperdrive(address(hyperdrive)),
            IERC20(address(baseToken)),
            testCase.mintPercent,
            "Bond",
            "BND"
        );

        vm.stopPrank();
        vm.startPrank(testCase.user);

        bondWrapper.setBalanceOf(testCase.user, testCase.userMintAmount);
        bondWrapper.setDeposits(
            testCase.user,
            testCase.assetId,
            testCase.userDeposit
        );

        // Mint bondWrapper underlying user is to receive
        baseToken.burn(
            address(bondWrapper),
            baseToken.balanceOf(address(bondWrapper))
        );
        baseToken.mint(address(bondWrapper), testCase.bondWrapperBase);

        hyperdrive.__setCloseLongReturnValue__(testCase.receivedAmount);

        // Set timestamp
        vm.warp(testCase.blockTimestamp);
    }

    function __fail(TestCase memory testCase) internal __combinatorial_fail {
        // Received amount of underlying must be at least some bps increase than
        // the amount specified
        bool unbackedPosition = testCase.receivedAmount <
            testCase.mintedFromBonds;
        // If amount of user's bond deposits is less than the amount specified
        // the transaction will underflow
        bool userDepositUnderflow = testCase.userDeposit < testCase.amount;
        // Will underflow if balance of wrapped bonds user has is less than the
        // amount burned
        bool userWrappedBondUnderflow = testCase.andBurn &&
            testCase.userMintAmount < testCase.mintedFromBonds;
        // Should fail to transfer if amount of base on contract does not exist
        // for the user to redeem
        bool baseTokenTransferWillFail = !unbackedPosition &&
            testCase.bondWrapperBase < testCase.userFunds;

        if (userDepositUnderflow) {
            __fail_error = stdError.arithmeticError;
        } else if (unbackedPosition) {
            __fail_error = abi.encodeWithSelector(
                Errors.InsufficientPrice.selector
            );
        } else if (userWrappedBondUnderflow) {
            __fail_error = stdError.arithmeticError;
        } else if (baseTokenTransferWillFail) {
            __fail_error = bytes("ERC20: transfer amount exceeds balance");
        }

        if (
            unbackedPosition ||
            userDepositUnderflow ||
            userWrappedBondUnderflow ||
            baseTokenTransferWillFail
        ) {
            try
                bondWrapper.close(
                    testCase.maturityTime,
                    testCase.amount,
                    testCase.andBurn,
                    testCase.destination
                )
            {
                __log(unicode"❎", testCase);
                revert ExpectedFail();
            } catch Error(string memory reason) {
                __error = bytes(reason);
            } catch (bytes memory e) {
                // NOTE: __error and __fail_error must be assigned here to
                // validate failure reason
                __error = e;
            }
        }
    }

    event __CloseLong__(
        uint256 indexed _maturityTime,
        uint256 indexed _bondAmount,
        uint256 indexed _minOutput,
        address _destination,
        bool _asUnderlying
    );

    event Transfer(address indexed from, address indexed to, uint256 value);

    function __success(
        TestCase memory testCase
    ) internal __combinatorial_success {
        // There are two code paths which calls hyperdrive.closeLong(),
        // dependent on whether the long is matured. In the case it has all
        // longs (of that assetId) are closed. In the case it hasn't matured
        // just the users longs are expected to be closed.
        vm.expectEmit(true, true, true, true);
        if (testCase.maturityTime > testCase.blockTimestamp) {
            emit __CloseLong__(
                testCase.maturityTime,
                testCase.amount,
                0,
                address(bondWrapper),
                true
            );
        } else {
            emit __CloseLong__(
                testCase.maturityTime,
                1,
                1,
                address(bondWrapper),
                true
            );
        }

        // A users wrapped long tokens should be burned if they specify to do so
        if (testCase.andBurn) {
            vm.expectEmit(true, true, true, true);
            emit Transfer(testCase.user, address(0), testCase.mintedFromBonds);
        }

        // Some amount of baseToken should be sent to the user
        vm.expectEmit(true, true, true, true);
        emit Transfer(
            address(bondWrapper),
            testCase.destination,
            testCase.userFunds
        );

        // Caching balances prior to executing transaction for differentials
        uint256 userDeposit = bondWrapper.deposits(
            testCase.user,
            testCase.assetId
        );
        uint256 userWrappedBondBalance = bondWrapper.balanceOf(testCase.user);
        uint256 bondWrapperBaseBalance = baseToken.balanceOf(
            address(bondWrapper)
        );
        uint256 destinationBaseBalance = baseToken.balanceOf(
            address(testCase.destination)
        );

        try
            bondWrapper.close(
                testCase.maturityTime,
                testCase.amount,
                testCase.andBurn,
                testCase.destination
            )
        {} catch {
            __log(unicode"❎", testCase);
            revert ExpectedSuccess();
        }

        // The bondWrapper contract records deposits of bonds per user. It is
        // expected for this to decrease by the amount of bonds passed to the
        // function
        uint256 userDepositDiff = userDeposit -
            bondWrapper.deposits(testCase.user, testCase.assetId);
        if (userDepositDiff != testCase.amount) {
            __log(unicode"❎", testCase);
            assertEq(
                userDepositDiff,
                testCase.amount,
                "expect user bond deposits to have decreased by amount"
            );
        }

        // The users wrapped bonds balance should decrease by the wrapped bonds
        // value of amount provided they have specified to burn those tokens
        uint256 userWrappedBondDiff = userWrappedBondBalance -
            bondWrapper.balanceOf(testCase.user);
        if (
            testCase.andBurn && userWrappedBondDiff != testCase.mintedFromBonds
        ) {
            __log(unicode"❎", testCase);
            assertEq(
                userWrappedBondDiff,
                testCase.mintedFromBonds,
                "expect user wrapped bonds to have been burned on redemption"
            );
        }

        // Should expect an amount of base to be transferred from the bond
        // wrapper contract
        uint256 bondWrapperBaseDiff = bondWrapperBaseBalance -
            baseToken.balanceOf(address(bondWrapper));
        if (bondWrapperBaseDiff != testCase.userFunds) {
            __log(unicode"❎", testCase);
            assertEq(
                bondWrapperBaseDiff,
                testCase.userFunds,
                "expect bond wrapper balance of base tokens to have decreased"
            );
        }

        // Should expect an amount of base to be transferred to the destination
        // specified by the user
        uint256 destinationBaseDiff = baseToken.balanceOf(
            address(testCase.destination)
        ) - destinationBaseBalance;
        if (destinationBaseDiff != testCase.userFunds) {
            __log(unicode"❎", testCase);
            assertEq(
                destinationBaseDiff,
                testCase.userFunds,
                "expect destination to have received base tokens"
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
        console2.log("\tandBurn                = ", testCase.andBurn);
        console2.log("\tdestination            = ", testCase.destination);
        console2.log("\tblockTimestamp         = ", testCase.blockTimestamp);
        console2.log("\treceivedAmount         = ", testCase.receivedAmount);
        console2.log("\tmintPercent            = ", testCase.mintPercent);
        console2.log("\tuser                   = ", testCase.user);
        console2.log("\tuserDeposit            = ", testCase.userDeposit);
        console2.log("\tuserMintAmount         = ", testCase.userMintAmount);
        console2.log("\tbondWrapperBase        = ", testCase.bondWrapperBase);
        console2.log("");
    }
}
