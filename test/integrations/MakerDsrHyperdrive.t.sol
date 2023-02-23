// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import { BaseTest } from "test/Test.sol";
import { MockMakerDsrHyperdrive, DsrManager } from "test/mocks/MockMakerDsrHyperdrive.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";

contract MakerDsrHyperdrive is BaseTest {
    using FixedPointMath for uint256;
    MockMakerDsrHyperdrive hyperdrive;
    IERC20 dai;
    DsrManager dsrManager;

    string MAINNET_RPC_URL =
        "https://eth-mainnet.alchemyapi.io/v2/kwjMP-X-Vajdk1ItCfU-56Uaq1wwhamK";

    error DaiMintError();

    function setUp() public override {
        // Fork to mainnet to use Maker
        uint256 mainnetForkId = vm.createFork(
            "https://eth-mainnet.alchemyapi.io/v2/kwjMP-X-Vajdk1ItCfU-56Uaq1wwhamK"
        );
        vm.selectFork(mainnetForkId);
        // DSR is at 1% here
        vm.rollFork(16_685_972);

        super.setUp();

        dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
        dsrManager = DsrManager(
            address(0x373238337Bfe1146fb49989fc222523f83081dDb)
        );

        vm.startPrank(deployer);
        hyperdrive = new MockMakerDsrHyperdrive(dai, dsrManager);
        vm.stopPrank();

        // Impersonate zero address and send dai to Alice
        vm.startPrank(address(0x0));
        vm.deal(address(0x0), 1 ether);
        uint256 zeroAddressDaiBalance = dai.balanceOf(address(0x0));
        dai.transfer(alice, zeroAddressDaiBalance);
        vm.stopPrank();
        vm.startPrank(alice);
        dai.approve(address(hyperdrive), type(uint256).max);

    }

    function test__dai_token_is_approved() public {
        uint256 allowance = dai.allowance(
            address(hyperdrive),
            address(dsrManager)
        );
        assertEq(
            allowance,
            type(uint256).max,
            "dsrManager should be an approved DAI spender of hyperdrive"
        );
    }


    function test__initial_deposit() public {
        // as Alice
        vm.stopPrank();
        vm.startPrank(alice);

        uint256 preBaseBalance = dai.balanceOf(alice);
        uint256 depositAmount = 2500e18;

        (uint256 shares, uint256 sharePrice) = hyperdrive.deposit(depositAmount);

        assertEq(shares, depositAmount, "initial shares should be 1:1 with base");
        assertEq(sharePrice, 1e18, "initial share price should be 1");

        uint256 postBaseBalance = dai.balanceOf(alice);
        assertEq(preBaseBalance - postBaseBalance, depositAmount);
    }

    function test__accrue_year_interest() public {
        // as Alice
        vm.stopPrank();
        vm.startPrank(alice);

        uint256 preBaseBalance = dai.balanceOf(alice);
        uint256 depositAmount = 2500e18;
        hyperdrive.deposit(depositAmount);

        vm.warp(block.timestamp + 365 days); // accrue 1% APY

        assertEq(hyperdrive.pricePerShare(), 1.01e18, "b");

        // // initial balance of Alice
        // uint256 preBaseBalance = dai.balanceOf(alice);
        // // approve Hyperdrive
        // dai.approve(address(hyperdrive), type(uint256).max);
        // // amount to be deposited
        // uint256 base = 2500e18;
        // // deposit
        // (uint256 shares1, uint256 sharePrice1) = hyperdrive.deposit(base);
        // // sharePrice will be off by 1 due to rounding
        // assertApproxEqAbs(
        //     sharePrice1,
        //     hyperdrive.pricePerShare(),
        //     1,
        //     "price invariant"
        // );

        // // fast-forward 1 year

        // console2.log("sharePrice2: %s", hyperdrive.pricePerShare());

        // (uint256 shares2, uint256 sharePrice2) = hyperdrive.deposit(base);
        // console2.log("shares2: %s", shares2);
        // // sharePrice will be off by 1 due to rounding
        // // Fails as shares are
        // assertApproxEqAbs(
        //     sharePrice2,
        //     hyperdrive.pricePerShare(),
        //     1,
        //     "price invariant"
        // );

        // uint256 sixMonthBalance = dsrManager.daiBalance(address(hyperdrive));
        // assertApproxEqAbs(base.mulDown(0.005e18), sixMonthBalance - base, 0.05e18);
        // console2.log("sharePrice: %s", sharePrice1);

        // // withdraw using shares
        //  hyperdrive.withdraw(shares, alice);
        //  // balance after setup
        //  uint256 postBaseBalance = dai.balanceOf(alice);
        //  // calculate accrued interest via differentials
        //  uint256 interest = postBaseBalance - preBaseBalance;
        //  assertApproxEqAbs(base.mulDown(0.01e18), interest, 100); // 5000 * 1% = 50
    }
}
