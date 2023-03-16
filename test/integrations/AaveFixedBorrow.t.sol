// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.sol";
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
    function setUp() public override __goerli_fork(8659000) {
        super.setUp();

        wsteth = IERC20Permit(
            address(0x6E4F1e8d4c5E5E6e2781FD814EE0744cc16Eb352)
        );
        dai = IERC20Permit(address(0x11fE4B6AE13d2a6055C8D9cF65c55bac32B5d844));

        pool = IPool(address(0x26ca51Af4506DE7a6f0785D20CD776081a05fF6d));

        hyperdrive = IHyperdrive(
            address(0x27b8C295f59f313898b49AfAde92CB430F8b4074)
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

    function test__aave_fixed_borrow_supply() public {
        wsteth.approve(address(action), type(uint256).max);
        ICreditDelegationToken(
            address(0xa99d874d26BdfD94d474Aa04f4f7861DCD55Cbf4)
        ).approveDelegation(address(action), type(uint256).max);

        // Expect wsteth supply to be made by the action contract
        // on behalf of alice
        vm.expectEmit(true, true, true, true);
        emit Supply(address(wsteth), address(action), alice, 10e18, 0);

        // Expect that an amount of dai to be borrowed on behalf of Alice
        vm.expectEmit(true, true, true, false);
        emit Borrow(
            address(dai),
            address(action),
            alice,
            500e18,
            DataTypes.InterestRateMode.VARIABLE,
            0,
            0
        );

        // TODO Replace this constraint with calculations for base deposited to
        // short
        //
        // Expect a transfer from action to hyperdrive
        vm.expectEmit(true, true, false, false);
        emit Transfer(address(action), address(hyperdrive), 0);


        vm.expectEmit(true, true, true, false);
        emit Repay(address(dai), alice, address(action), 0, false);

        uint256 baseDeposited = action.supplyBorrowAndOpenShort(
            address(wsteth),
            10e18,
            500e18,
            15000e18,
            500e18
        );

        // TODO Fix
        assertApproxEqAbs(baseDeposited, 407e18, 1e18);
    }
}
