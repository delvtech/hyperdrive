// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { ERC4626HyperdriveDeployer } from "contracts/src/factory/ERC4626HyperdriveDeployer.sol";
import { ERC4626HyperdriveFactory } from "contracts/src/factory/ERC4626HyperdriveFactory.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { Mock4626, ERC20 } from "../mocks/Mock4626.sol";
import { MockERC4626Hyperdrive } from "../mocks/Mock4626Hyperdrive.sol";
import { HyperdriveUtils } from "../utils/HyperdriveUtils.sol";

contract HyperdriveER4626Test is HyperdriveTest {
    using FixedPointMath for *;

    ERC4626HyperdriveFactory factory;
    IERC20 dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
    IERC4626 pool;
    uint256 aliceShares;
    MockERC4626Hyperdrive mockHyperdrive;

    function setUp() public override __mainnet_fork(16_685_972) {
        vm.startPrank(deployer);

        // Deploy the ERC4626Hyperdrive factory and deployer.
        pool = IERC4626(
            address(new Mock4626(ERC20(address(dai)), "yearn dai", "yDai"))
        );

        ERC4626HyperdriveDeployer simpleDeployer = new ERC4626HyperdriveDeployer(
                pool
            );
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ForwarderFactory();
        factory = new ERC4626HyperdriveFactory(
            alice,
            simpleDeployer,
            bob,
            bob,
            IHyperdrive.Fees(0, 0, 0),
            defaults,
            address(forwarderFactory),
            forwarderFactory.ERC20LINK_HASH(),
            pool
        );

        address daiWhale = 0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8;
        whaleTransfer(daiWhale, dai, alice);

        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: dai,
            initialSharePrice: FixedPointMath.ONE_18,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: FixedPointMath.ONE_18.divDown(
                22.186877016851916266e18
            ),
            governance: address(0),
            feeCollector: address(0),
            fees: IHyperdrive.Fees(0, 0, 0),
            oracleSize: 2,
            updateGap: 0
        });

        // Create a mock hyperdrive with functions available
        mockHyperdrive = new MockERC4626Hyperdrive(
            config,
            address(0),
            bytes32(0),
            address(0),
            pool
        );

        vm.stopPrank();
        vm.startPrank(alice);
        dai.approve(address(hyperdrive), type(uint256).max);
        dai.approve(address(mockHyperdrive), type(uint256).max);
        dai.approve(address(pool), type(uint256).max);
        aliceShares = pool.deposit(10e18, alice);

        vm.stopPrank();
        vm.startPrank(bob);
        dai.approve(address(hyperdrive), type(uint256).max);
        dai.approve(address(mockHyperdrive), type(uint256).max);
        vm.stopPrank();

        // Start recording events.
        vm.recordLogs();
    }

    function test_erc4626_deposit() external {
        setUp();
        // First we add some interest
        vm.startPrank(alice);
        dai.transfer(address(pool), 5e18);
        // Now we try a deposit
        (uint256 sharesMinted, uint256 sharePrice) = mockHyperdrive.deposit(
            1e18,
            true
        );
        assertEq(sharePrice, 1.5e18 + 1);
        // 0.6 repeating
        assertEq(sharesMinted, 666666666666666666);
        assertEq(pool.balanceOf(address(mockHyperdrive)), 666666666666666666);

        // Now we try to do a deposit from alice's shares
        pool.approve(address(mockHyperdrive), type(uint256).max);
        (sharesMinted, sharePrice) = mockHyperdrive.deposit(3e18, false);
        assertEq(sharePrice, 1.5e18 + 1);
        assertApproxEqAbs(sharesMinted, 2e18, 1);
        assertApproxEqAbs(
            pool.balanceOf(address(mockHyperdrive)),
            2666666666666666666,
            2
        );
    }

    function test_erc4626_withdraw() external {
        setUp();
        // First we add some shares and interest
        vm.startPrank(alice);
        dai.transfer(address(pool), 5e18);
        pool.transfer(address(mockHyperdrive), 10e18);
        uint256 balanceBefore = dai.balanceOf(alice);
        // test an underlying withdraw
        uint256 amountWithdrawn = mockHyperdrive.withdraw(2e18, alice, true);
        uint256 balanceAfter = dai.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore + 3e18);
        assertEq(amountWithdrawn, 3e18);

        // Test a share withdraw
        amountWithdrawn = mockHyperdrive.withdraw(2e18, alice, false);
        assertEq(pool.balanceOf(alice), 2e18);
        assertEq(amountWithdrawn, 3e18);
    }

    function test_erc4626_pricePerShare() external {
        setUp();
        // First we add some shares and interest
        vm.startPrank(alice);
        dai.transfer(address(pool), 2e18);

        uint256 price = mockHyperdrive.pricePerShare();
        assertEq(price, 1.2e18);
    }

    function test_erc4626_testDeploy() external {
        setUp();
        vm.startPrank(alice);
        uint256 apr = 0.01e18; // 1% apr
        uint256 contribution = 2_500e18;
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: dai,
            initialSharePrice: FixedPointMath.ONE_18,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: HyperdriveUtils.calculateTimeStretch(apr),
            governance: address(0),
            feeCollector: address(0),
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
        assertEq(createdShares, 2500e18-1e4);

        // Verify that the correct events were emitted.
        verifyFactoryEvents(
            factory,
            alice,
            contribution,
            apr,
            new bytes32[](0)
        );
    }
}
