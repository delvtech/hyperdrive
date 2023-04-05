// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { AaveFixedBorrowAction, IHyperdrive, IPool } from "contracts/src/actions/AaveFixedBorrow.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { DsrManager } from "contracts/src/interfaces/IMaker.sol";
import { IERC20Mint } from "contracts/src/interfaces/IERC20Mint.sol";
import { IERC20Permit } from "contracts/src/interfaces/IERC20Permit.sol";
import { ICreditDelegationToken } from "@aave/interfaces/ICreditDelegationToken.sol";
import { DataTypes } from "@aave/protocol/libraries/types/DataTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AaveFixedBorrowTest is BaseTest {
    using FixedPointMath for uint256;

    AaveFixedBorrowAction action;
    IHyperdrive hyperdrive;
    IPool pool;
    IERC20Permit dai;
    IERC20Permit wsteth;

    // Token addresses taken from:
    // https://github.com/phoenixlabsresearch/sparklend/blob/master/script/output/5/spark-latest.json
    function setUp() public override __goerli_fork(8749473) {
        super.setUp();

        wsteth = IERC20Permit(
            address(0x6E4F1e8d4c5E5E6e2781FD814EE0744cc16Eb352)
        );
        dai = IERC20Permit(address(0x11fE4B6AE13d2a6055C8D9cF65c55bac32B5d844));

        pool = IPool(address(0x26ca51Af4506DE7a6f0785D20CD776081a05fF6d));

        hyperdrive = IHyperdrive(
            address(0xB311B825171AF5A60d69aAD590B857B1E5ed23a2)
        );

        action = new AaveFixedBorrowAction(hyperdrive, pool);

        vm.stopPrank();
        vm.startPrank(alice);
        IERC20Mint(address(wsteth)).mint(1000e18);

        action.setApproval(address(wsteth), address(pool), type(uint256).max);
        action.setApproval(address(dai), address(pool), type(uint256).max);
        action.setApproval(
            address(dai),
            address(hyperdrive),
            type(uint256).max
        );
    }

    function test__aave_fixed_borrow_init() public {
        assertEq(address(action.debtToken()), address(dai));
    }

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Supply(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint16 indexed referralCode
    );

    event Borrow(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        DataTypes.InterestRateMode interestRateMode,
        uint256 borrowRate,
        uint16 indexed referralCode
    );

    event Repay(
        address indexed reserve,
        address indexed user,
        address indexed repayer,
        uint256 amount,
        bool useATokens
    );

    event SupplyBorrowAndOpenShort(
        uint256 costOfShort,
        address indexed who,
        address assetBorrowed,
        uint256 amountBorrowed
    );

    function test__supply_borrow_and_open_short() public {
        wsteth.approve(address(action), type(uint256).max);
        ICreditDelegationToken(
            address(0xa99d874d26BdfD94d474Aa04f4f7861DCD55Cbf4)
        ).approveDelegation(address(action), type(uint256).max);

        uint256 supplyAmount = 10e18;
        uint256 borrowAmount = 500e18;
        uint256 bondAmount = 15000e18;

        // Calculate the amount of base deposit needed for the short
        uint256 calculatedDeposit = HyperdriveUtils.calculateOpenShortDeposit(
            hyperdrive,
            bondAmount
        );

        // Add a small buffer of capital so that the loan is repaid
        uint256 maxDeposit = calculatedDeposit + 1.1e18;

        // Expect wsteth supply to be made by the action contract
        // on behalf of alice
        vm.expectEmit(true, true, true, true);
        emit Supply(address(wsteth), address(action), alice, supplyAmount, 0);

        // Expect that an amount of dai to be borrowed on behalf of Alice
        vm.expectEmit(true, true, true, false);
        emit Borrow(
            address(dai),
            address(action),
            alice,
            borrowAmount + maxDeposit,
            DataTypes.InterestRateMode.VARIABLE,
            0,
            0
        );
        // deposit of base should be transferred to hyperdrive for the short
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(action), address(hyperdrive), calculatedDeposit);

        // Excess borrowings should be repaid into alice's loan
        vm.expectEmit(true, true, true, true);
        emit Repay(
            address(dai),
            alice,
            address(action),
            maxDeposit - calculatedDeposit,
            false
        );

        // Alice should receive the amount of specified borrowings
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(action), alice, borrowAmount);

        // Make the hedged loan and track Alice's dai balance
        uint256 daiBalanceBefore = dai.balanceOf(alice);
        uint256 deposit = action.supplyBorrowAndOpenShort(
            address(wsteth),
            supplyAmount,
            borrowAmount,
            bondAmount,
            maxDeposit
        );
        uint256 daiBalanceAfter = dai.balanceOf(alice);

        // Alice should receive the amount of specified borrowings
        vm.expectEmit(true, true, false, true);
        emit SupplyBorrowAndOpenShort(
            calculatedDeposit,
            alice,
            address(wsteth),
            borrowAmount
        );

        assertEq(deposit, calculatedDeposit);
        assertEq(daiBalanceAfter - daiBalanceBefore, borrowAmount);
    }
}
