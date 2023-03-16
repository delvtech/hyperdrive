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
    function setUp() public override __goerli_fork(8666586) {
        super.setUp();

        wsteth = IERC20Permit(
            address(0x6E4F1e8d4c5E5E6e2781FD814EE0744cc16Eb352)
        );
        dai = IERC20Permit(address(0x11fE4B6AE13d2a6055C8D9cF65c55bac32B5d844));

        pool = IPool(address(0x26ca51Af4506DE7a6f0785D20CD776081a05fF6d));

        hyperdrive = IHyperdrive(
            address(0xEf99A9De7cf59db2F2b45656c48E2D2733Cc9B3e)
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

        uint256 supplyAmount = 10e18;
        uint256 borrowAmount = 500e18;
        uint256 bondAmount = 15000e18;

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
            borrowAmount,
            DataTypes.InterestRateMode.VARIABLE,
            0,
            0
        );

        uint256 baseForShort = HyperdriveUtils.calculateBaseForOpenShort(
            hyperdrive,
            bondAmount
        );

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(action), address(hyperdrive), baseForShort);

        vm.expectEmit(true, true, true, true);
        emit Repay(
            address(dai),
            alice,
            address(action),
            borrowAmount - baseForShort,
            false
        );

        uint256 baseDeposited = action.supplyBorrowAndOpenShort(
            address(wsteth),
            supplyAmount,
            borrowAmount,
            bondAmount,
            baseForShort // use as maxDeposit
        );

        assertEq(baseDeposited, baseForShort);
    }
}
