// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IPool } from "@aave/interfaces/IPool.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { AaveHyperdriveDeployer } from "contracts/src/factory/AaveHyperdriveDeployer.sol";
import { AaveHyperdriveFactory } from "contracts/src/factory/AaveHyperdriveFactory.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { Mock4626, ERC20 } from "../mocks/Mock4626.sol";
import { MockAaveHyperdrive } from "../mocks/MockAaveHyperdrive.sol";
import { HyperdriveUtils } from "../utils/HyperdriveUtils.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";

contract AaveHyperdriveTest is HyperdriveTest {
    using FixedPointMath for *;

    AaveHyperdriveFactory factory;
    IERC20 dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
    IPool pool = IPool(address(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2));
    IERC20 aDAI = IERC20(address(0x018008bfb33d285247A21d44E50697654f754e63));
    uint256 aliceShares;
    MockAaveHyperdrive mockHyperdrive;

    function setUp() public override __mainnet_fork(16_685_972) {
        alice = createUser("alice");
        bob = createUser("bob");

        vm.startPrank(deployer);

        AaveHyperdriveDeployer simpleDeployer = new AaveHyperdriveDeployer(
            pool
        );
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ForwarderFactory();
        factory = new AaveHyperdriveFactory(
            alice,
            simpleDeployer,
            bob,
            bob,
            IHyperdrive.Fees(0, 0, 0),
            defaults,
            address(forwarderFactory),
            forwarderFactory.ERC20LINK_HASH()
        );

        address daiWhale = 0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8;
        whaleTransfer(daiWhale, dai, alice);
        whaleTransfer(daiWhale, dai, bob);

        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: dai,
            initialSharePrice: FixedPointMath.ONE_18,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: FixedPointMath.ONE_18.divDown(
                22.186877016851916266e18
            ),
            governance: alice,
            feeCollector: bob,
            fees: IHyperdrive.Fees(0, 0, 0),
            oracleSize: 2,
            updateGap: 0
        });

        // Create a mock hyperdrive with functions available
        mockHyperdrive = new MockAaveHyperdrive(
            config,
            address(0),
            bytes32(0),
            address(0),
            aDAI,
            pool
        );

        vm.stopPrank();
        vm.startPrank(alice);
        dai.approve(address(hyperdrive), type(uint256).max);
        dai.approve(address(mockHyperdrive), type(uint256).max);
        dai.approve(address(pool), type(uint256).max);
        pool.supply(address(dai), 100e18, alice, 0);

        vm.stopPrank();
        vm.startPrank(bob);
        dai.approve(address(hyperdrive), type(uint256).max);
        dai.approve(address(mockHyperdrive), type(uint256).max);
        vm.stopPrank();

        // Start recording events.
        vm.recordLogs();
    }

    function test_aave_hyperdrive_deposit() external {
        vm.startPrank(alice);
        // Do a first deposit
        (uint256 sharesMinted, uint256 sharePrice) = mockHyperdrive.deposit(
            10e18,
            true
        );
        assertEq(sharePrice, 1e18);
        // 0.6 repeating
        assertEq(sharesMinted, 10e18);
        assertEq(aDAI.balanceOf(address(mockHyperdrive)), 10e18);

        // add interest
        aDAI.transfer(address(mockHyperdrive), 5e18);
        // Now we try a deposit
        (sharesMinted, sharePrice) = mockHyperdrive.deposit(1e18, true);
        assertEq(sharePrice, 1.5e18);
        // 0.6 repeating
        assertEq(sharesMinted, 666666666666666666);
        assertEq(aDAI.balanceOf(address(mockHyperdrive)), 16e18);

        // Now we try to do a deposit from alice's aDAI
        aDAI.approve(address(mockHyperdrive), type(uint256).max);
        (sharesMinted, sharePrice) = mockHyperdrive.deposit(3e18, false);
        assertEq(sharePrice, 1.5e18);
        assertApproxEqAbs(sharesMinted, 2e18, 1);
        assertApproxEqAbs(aDAI.balanceOf(address(mockHyperdrive)), 19e18, 2);
    }

    function test_aave_hyperdrive_withdraw() external {
        // First we add some shares and interest
        vm.startPrank(alice);
        //init pool
        mockHyperdrive.deposit(10e18, true);
        // add interest
        aDAI.transfer(address(mockHyperdrive), 5e18);

        uint256 balanceBefore = dai.balanceOf(alice);
        // test an underlying withdraw
        uint256 amountWithdrawn = mockHyperdrive.withdraw(2e18, alice, true);
        uint256 balanceAfter = dai.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore + 3e18);
        assertEq(amountWithdrawn, 3e18);

        // Test a share withdraw
        balanceBefore = aDAI.balanceOf(alice);
        amountWithdrawn = mockHyperdrive.withdraw(2e18, alice, false);
        assertEq(aDAI.balanceOf(alice), 3e18 + balanceBefore);
        assertEq(amountWithdrawn, 3e18);

        // Check the zero withdraw revert
        vm.expectRevert(Errors.NoAssetsToWithdraw.selector);
        mockHyperdrive.withdraw(0, alice, false);
    }

    function test_aave_hyperdrive_pricePerShare() external {
        // First we add some shares and interest
        vm.startPrank(alice);
        // check it's zero before deposit
        assertEq(0, mockHyperdrive.pricePerShare());
        // deposit the initial shares
        mockHyperdrive.deposit(10e18, true);
        // add interest
        aDAI.transfer(address(mockHyperdrive), 2e18);

        uint256 price = mockHyperdrive.pricePerShare();
        assertEq(price, 1.2e18);
    }

    function test_aave_hyperdrive_testDeploy() external {
        vm.startPrank(alice);
        uint256 apr = 0.01e18; // 1% apr
        uint256 contribution = 2_500e18;
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: dai,
            initialSharePrice: FixedPointMath.ONE_18,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: HyperdriveUtils.calculateTimeStretch(apr),
            governance: alice,
            feeCollector: bob,
            fees: IHyperdrive.Fees(0, 0, 0),
            oracleSize: 2,
            updateGap: 0
        });
        dai.approve(address(factory), type(uint256).max);
        hyperdrive = factory.deployAndInitialize(
            config,
            new bytes32[](0),
            contribution,
            apr
        );

        // The initial price per share is one so we should have that the
        // shares in the alice account are 1
        uint256 createdShares = hyperdrive.balanceOf(
            AssetId._LP_ASSET_ID,
            alice
        );
        // lp shares should equal number of share reserves initialized with
        assertEq(createdShares, 2500e18 - 1e5);

        bytes32[] memory aDaiEncoding = new bytes32[](1);
        aDaiEncoding[0] = bytes32(uint256(uint160(address(aDAI))));
        // Verify that the correct events were emitted.
        verifyFactoryEvents(
            factory,
            alice,
            contribution - 1e5,
            apr,
            aDaiEncoding
        );

        // Test the revert condition for eth payment
        vm.expectRevert(Errors.NotPayable.selector);
        hyperdrive = factory.deployAndInitialize{ value: 100 }(
            config,
            new bytes32[](0),
            contribution,
            apr
        );

        config.baseToken = IERC20(address(0));
        vm.expectRevert(Errors.InvalidToken.selector);
        hyperdrive = factory.deployAndInitialize(
            config,
            new bytes32[](0),
            2500e18,
            //1% apr
            1e16
        );
    }
}
