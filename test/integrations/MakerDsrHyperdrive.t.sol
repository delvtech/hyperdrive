// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import { BaseTest } from "test/Test.sol";
import { MockMakerDsrHyperdrive, DsrManager, Chai } from "test/mocks/MockMakerDsrHyperdrive.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";

contract MakerDsrHyperdrive is BaseTest {
    using FixedPointMath for uint256;

    MockMakerDsrHyperdrive hyperdrive;
    IERC20 dai;
    IERC20 chai;
    DsrManager dsrManager;

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
        chai = IERC20(address(0x06AF07097C9Eeb7fD685c692751D5C66dB49c215));
        dsrManager = DsrManager(
            address(0x373238337Bfe1146fb49989fc222523f83081dDb)
        );

        vm.startPrank(deployer);
        hyperdrive = new MockMakerDsrHyperdrive(dai, chai, dsrManager);
        vm.stopPrank();

        address chaiWhale = 0x602f2E120A9956F2Ad1cE47cED286fcEfbBa9f8C;
        address daiWhale = 0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8;

        whaleTransfer(chaiWhale, chai, alice);
        whaleTransfer(daiWhale, dai, alice);

        vm.stopPrank();
        vm.startPrank(alice);
        dai.approve(address(hyperdrive), type(uint256).max);
        chai.approve(address(hyperdrive), type(uint256).max);

        vm.stopPrank();
        vm.startPrank(bob);
        dai.approve(address(hyperdrive), type(uint256).max);
        chai.approve(address(hyperdrive), type(uint256).max);
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

    function test__initial_base_token_deposit() public {
        // as Alice
        vm.stopPrank();
        vm.startPrank(alice);

        uint256 preBaseBalance = dai.balanceOf(alice);
        uint256 depositAmount = 2500e18;

        (uint256 shares, uint256 sharePrice) = hyperdrive.deposit(
            depositAmount,
            true
        );

        assertEq(
            shares,
            depositAmount,
            "initial shares should be 1:1 with base"
        );
        assertEq(sharePrice, 1e18, "initial share price should be 1");

        uint256 postBaseBalance = dai.balanceOf(alice);
        assertEq(
            preBaseBalance - postBaseBalance,
            depositAmount,
            "hyperdrive should have transferred tokens"
        );
    }

    function test__initial_share_token_deposit() public {
        // as Alice
        vm.stopPrank();
        vm.startPrank(alice);

        uint256 preBaseBalance = chai.balanceOf(alice);
        uint256 depositAmount = 1000e18;

        (uint256 shares, uint256 sharePrice) = hyperdrive.deposit(
            depositAmount,
            false
        );

        assertEq(
            shares,
            depositAmount.mulDivDown(hyperdrive.chi(), hyperdrive.RAY()),
            "initial shares should be 1:1 with the base value of the shareTokens"
        );
        assertEq(sharePrice, 1e18, "initial share price should be 1");

        uint256 postBaseBalance = chai.balanceOf(alice);
        assertEq(
            preBaseBalance - postBaseBalance,
            depositAmount,
            "hyperdrive should have transferred tokens"
        );
    }

    function test__pricePerShare() public {
        // as Alice
        vm.stopPrank();
        vm.startPrank(alice);

        hyperdrive.deposit(1000e18, true);
        vm.warp(block.timestamp + 365 days); // accrue 1% APY

        uint256 pricePerShare = hyperdrive.pricePerShare();
        assertApproxEqAbs(
            pricePerShare,
            1.01e18,
            1,
            "pricePerShare should have increased 1% in value"
        );

        (, uint256 sharePrice) = hyperdrive.deposit(1000e18, true);

        assertApproxEqAbs(
            pricePerShare,
            sharePrice,
            1,
            "emulated share price should match pool ratio on deposit"
        );
    }

    function test__multiple_deposits() public {
        // as Alice
        vm.stopPrank();
        vm.startPrank(alice);

        // deposit into pool
        (uint256 sharesAlice, ) = hyperdrive.deposit(4545e18, true);

        // transfer to Bob and accrue interest in the pool
        dai.transfer(bob, 1000e18);
        vm.warp(block.timestamp + 1212 days + 54); // accrue 1% APY

        vm.stopPrank();
        vm.startPrank(bob);

        (uint256 sharesBob, ) = hyperdrive.deposit(1000e18, true);
        // accrue another year
        vm.warp(block.timestamp + 365 days); // accrue 1% APY

        uint256 pricePerShare = hyperdrive.pricePerShare();

        uint256 underlyingForBob = sharesBob.mulDown(pricePerShare);
        uint256 underlyingForAlice = sharesAlice.mulDown(pricePerShare);

        uint256 underlyingInPool = dsrManager.daiBalance(address(hyperdrive));

        assertApproxEqAbs(
            underlyingForBob,
            1010e18,
            5000,
            "Bob should have accrued 1% interest"
        );
        assertApproxEqAbs(
            underlyingForAlice,
            underlyingInPool - underlyingForBob,
            5000,
            "Alice's shares should reflect all remaining deposits"
        );
    }

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
