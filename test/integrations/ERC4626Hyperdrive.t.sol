// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626HyperdriveDeployer } from "contracts/src/factory/ERC4626HyperdriveDeployer.sol";
import { ERC4626HyperdriveFactory } from "contracts/src/factory/ERC4626HyperdriveFactory.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { ERC4626DataProvider } from "contracts/src/instances/ERC4626DataProvider.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { Mock4626, ERC20 } from "../mocks/Mock4626.sol";
import { MockERC4626Hyperdrive } from "../mocks/Mock4626Hyperdrive.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../utils/HyperdriveUtils.sol";

contract ERC4626HyperdriveTest is HyperdriveTest {
    using FixedPointMath for *;

    ERC4626HyperdriveFactory factory;
    IERC20 dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
    IERC4626 pool;
    uint256 aliceShares;
    MockERC4626Hyperdrive mockHyperdrive;

    function setUp() public override __mainnet_fork(16_685_972) {
        alice = createUser("alice");
        bob = createUser("bob");

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
            HyperdriveFactory.FactoryConfig(
                alice,
                bob,
                bob,
                IHyperdrive.Fees(0, 0, 0),
                IHyperdrive.Fees(0, 0, 0),
                defaults
            ),
            simpleDeployer,
            address(forwarderFactory),
            forwarderFactory.ERC20LINK_HASH(),
            pool,
            new address[](0)
        );

        // Transfer a large amount of DAI to Alice.
        address daiWhale = 0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8;
        whaleTransfer(daiWhale, dai, alice);

        // Deploy a MockHyperdrive instance.
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: dai,
            baseDecimals: dai.decimals(),
            initialSharePrice: FixedPointMath.ONE_18,
            minimumShareReserves: FixedPointMath.ONE_18,
            minimumTransactionAmount: 0.001e18,
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
        address dataProvider = address(
            new ERC4626DataProvider(config, bytes32(0), address(0), pool)
        );
        mockHyperdrive = new MockERC4626Hyperdrive(
            config,
            dataProvider,
            bytes32(0),
            address(0),
            pool,
            new address[](0)
        );

        vm.stopPrank();
        vm.startPrank(alice);
        dai.approve(address(factory), type(uint256).max);
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
        // First we add some interest
        vm.startPrank(alice);
        dai.transfer(address(pool), 5e18);
        // Now we try a deposit
        (uint256 sharesMinted, uint256 sharePrice) = mockHyperdrive.deposit(
            1e18,
            true
        );
        assertEq(sharePrice, 1.5e18);
        // 0.6 repeating
        assertEq(sharesMinted, 666666666666666666);
        assertEq(pool.balanceOf(address(mockHyperdrive)), 666666666666666666);

        // Now we try to do a deposit from alice's shares
        pool.approve(address(mockHyperdrive), type(uint256).max);
        (sharesMinted, sharePrice) = mockHyperdrive.deposit(3e18, false);
        assertEq(sharePrice, 1.5e18);
        assertApproxEqAbs(sharesMinted, 2e18, 1);
        assertApproxEqAbs(
            pool.balanceOf(address(mockHyperdrive)),
            2666666666666666666,
            2
        );
    }

    function test_erc4626_withdraw() external {
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

    function test_erc4626_testDeploy() external {
        vm.startPrank(alice);
        uint256 apr = 0.01e18; // 1% apr
        uint256 contribution = 2_500e18;
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: dai,
            baseDecimals: dai.decimals(),
            initialSharePrice: FixedPointMath.ONE_18,
            minimumShareReserves: FixedPointMath.ONE_18,
            minimumTransactionAmount: 0.001e18,
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

        // The initial price per share is one so the LP shares will initially
        // be worth one base. Alice should receive LP shares equaling her
        // contribution minus the shares that she set aside for the minimum
        // share reserves and the zero address's initial LP contribution.
        assertEq(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            contribution - 2 * config.minimumShareReserves
        );

        // Verify that the correct events were emitted.
        verifyFactoryEvents(
            factory,
            alice,
            contribution,
            apr,
            config.minimumShareReserves,
            new bytes32[](0),
            0
        );
    }

    function test_erc4626_sharePrice() public {
        // This test makes sure that the ERC4626DataProvider function returns
        // the correct share price.
        vm.startPrank(alice);
        uint256 apr = 0.01e18; // 1% apr
        uint256 contribution = 2_500e18;
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: dai,
            baseDecimals: dai.decimals(),
            initialSharePrice: FixedPointMath.ONE_18,
            minimumShareReserves: FixedPointMath.ONE_18,
            minimumTransactionAmount: 0.001e18,
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

        // Ensure the share price is 1 after initialization.
        assertEq(hyperdrive.getPoolInfo().sharePrice, 1e18);

        // Simulate interest accrual by sending funds to the pool.
        dai.transfer(address(pool), contribution);

        // Ensure that the share price calculations are correct when share price is not equal to 1e18.
        assertEq(
            hyperdrive.getPoolInfo().sharePrice,
            (pool.totalAssets()).divDown(pool.totalSupply())
        );
    }

    function test_erc4626_updateSweepTargets() public {
        // Ensure that the sweep targets can be updated by governance.
        vm.startPrank(alice);
        address[] memory sweepTargets = new address[](2);
        sweepTargets[0] = address(bob);
        sweepTargets[1] = address(celine);
        factory.updateSweepTargets(sweepTargets);
        address[] memory updatedTargets = factory.getSweepTargets();
        assertEq(updatedTargets.length, 2);
        assertEq(updatedTargets[0], address(bob));
        assertEq(updatedTargets[1], address(celine));
        vm.stopPrank();

        // Ensure that the sweep targets cannot be updated by non-governance.
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateSweepTargets(sweepTargets);
    }

    function test_erc4626_sweep() public {
        // Ensure that deployment will fail if the pool or base token is
        // specified as a sweep target.
        vm.startPrank(alice);
        address[] memory sweepTargets = new address[](1);
        sweepTargets[0] = address(dai);
        factory.updateSweepTargets(sweepTargets);
        IHyperdrive.PoolConfig memory config = IHyperdrive(
            address(mockHyperdrive)
        ).getPoolConfig();
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        factory.deployAndInitialize(
            config,
            new bytes32[](0),
            1_000e18,
            0.05e18
        );
        assert(
            !ERC4626DataProvider(address(mockHyperdrive)).isSweepable(
                address(dai)
            )
        );
        sweepTargets[0] = address(pool);
        factory.updateSweepTargets(sweepTargets);
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        factory.deployAndInitialize(
            config,
            new bytes32[](0),
            1_000e18,
            0.05e18
        );
        assert(
            !ERC4626DataProvider(address(mockHyperdrive)).isSweepable(
                address(pool)
            )
        );
        vm.stopPrank();

        // Ensure that the base token and the pool cannot be swept.
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        mockHyperdrive.sweep(dai);
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        mockHyperdrive.sweep(IERC20(address(pool)));
        vm.stopPrank();

        // Ensure that a sweep target that isn't the base token or the pool
        // can be initialized and that the target can be swept successfully.
        vm.startPrank(alice);
        ERC20Mintable otherToken = new ERC20Mintable();
        sweepTargets[0] = address(otherToken);
        factory.updateSweepTargets(sweepTargets);
        mockHyperdrive = MockERC4626Hyperdrive(
            address(
                factory.deployAndInitialize(
                    config,
                    new bytes32[](0),
                    1_000e18,
                    0.05e18
                )
            )
        );
        assert(
            ERC4626DataProvider(address(mockHyperdrive)).isSweepable(
                address(otherToken)
            )
        );
        vm.stopPrank();
        vm.startPrank(bob);
        otherToken.mint(address(mockHyperdrive), 1e18);
        mockHyperdrive.sweep(IERC20(address(otherToken)));
        assertEq(otherToken.balanceOf(bob), 1e18);
        vm.stopPrank();

        // Alice should not be able to sweep the target since she isn't a pauser.
        vm.startPrank(alice);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        mockHyperdrive.sweep(IERC20(address(otherToken)));
        vm.stopPrank();

        // Bob adds Alice as a pauser.
        vm.startPrank(bob);
        mockHyperdrive.setPauser(alice, true);
        vm.stopPrank();

        // Alice should be able to sweep the target successfully.
        vm.startPrank(alice);
        otherToken.mint(address(mockHyperdrive), 1e18);
        mockHyperdrive.sweep(IERC20(address(otherToken)));
        assertEq(otherToken.balanceOf(bob), 2e18);
        vm.stopPrank();
    }
}
