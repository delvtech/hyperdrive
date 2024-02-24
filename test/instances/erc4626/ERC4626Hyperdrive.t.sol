// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC4626HyperdriveCoreDeployer } from "contracts/src/deployers/erc4626/ERC4626HyperdriveCoreDeployer.sol";
import { ERC4626HyperdriveDeployerCoordinator } from "contracts/src/deployers/erc4626/ERC4626HyperdriveDeployerCoordinator.sol";
import { ERC4626Target0Deployer } from "contracts/src/deployers/erc4626/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "contracts/src/deployers/erc4626/ERC4626Target1Deployer.sol";
import { ERC4626Target2Deployer } from "contracts/src/deployers/erc4626/ERC4626Target2Deployer.sol";
import { ERC4626Target3Deployer } from "contracts/src/deployers/erc4626/ERC4626Target3Deployer.sol";
import { ERC4626Target4Deployer } from "contracts/src/deployers/erc4626/ERC4626Target4Deployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { ERC4626Target0 } from "contracts/src/instances/erc4626/ERC4626Target0.sol";
import { ERC4626Target1 } from "contracts/src/instances/erc4626/ERC4626Target1.sol";
import { ERC4626Target2 } from "contracts/src/instances/erc4626/ERC4626Target2.sol";
import { ERC4626Target3 } from "contracts/src/instances/erc4626/ERC4626Target3.sol";
import { ERC4626Target4 } from "contracts/src/instances/erc4626/ERC4626Target4.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IERC4626Hyperdrive } from "contracts/src/interfaces/IERC4626Hyperdrive.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "contracts/src/interfaces/IHyperdriveDeployerCoordinator.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626, ERC20 } from "contracts/test/MockERC4626.sol";
import { MockERC4626Hyperdrive } from "contracts/test/MockERC4626Hyperdrive.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract ERC4626HyperdriveTest is HyperdriveTest {
    using FixedPointMath for *;

    HyperdriveFactory factory;

    address deployerCoordinator;
    address coreDeployer;
    address target0Deployer;
    address target1Deployer;
    address target2Deployer;
    address target3Deployer;
    address target4Deployer;

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
            address(
                new MockERC4626(
                    ERC20Mintable(address(dai)),
                    "yearn dai",
                    "yDai",
                    0,
                    address(0),
                    false
                )
            )
        );
        coreDeployer = address(new ERC4626HyperdriveCoreDeployer());
        target0Deployer = address(new ERC4626Target0Deployer());
        target1Deployer = address(new ERC4626Target1Deployer());
        target2Deployer = address(new ERC4626Target2Deployer());
        target3Deployer = address(new ERC4626Target3Deployer());
        target4Deployer = address(new ERC4626Target4Deployer());
        deployerCoordinator = address(
            new ERC4626HyperdriveDeployerCoordinator(
                coreDeployer,
                target0Deployer,
                target1Deployer,
                target2Deployer,
                target3Deployer,
                target4Deployer
            )
        );
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ERC20ForwarderFactory();
        factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: celine,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimeStretchAPR: 0.005e18,
                maxTimeStretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                }),
                maxFees: IHyperdrive.Fees({
                    curve: ONE,
                    flat: ONE,
                    governanceLP: ONE,
                    governanceZombie: ONE
                }),
                linkerFactory: address(forwarderFactory),
                linkerCodeHash: forwarderFactory.ERC20LINK_HASH()
            })
        );

        // Transfer a large amount of DAI to Alice.
        address daiWhale = 0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8;
        whaleTransfer(daiWhale, dai, alice);

        // Deploy a MockHyperdrive instance.
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: dai,
            linkerFactory: address(0),
            linkerCodeHash: bytes32(0),
            initialVaultSharePrice: ONE,
            minimumShareReserves: ONE,
            minimumTransactionAmount: 0.001e18,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: ONE.divDown(22.186877016851916266e18),
            governance: alice,
            feeCollector: bob,
            fees: IHyperdrive.Fees(0, 0, 0, 0)
        });
        address target0 = address(new ERC4626Target0(config, pool));
        address target1 = address(new ERC4626Target1(config, pool));
        address target2 = address(new ERC4626Target2(config, pool));
        address target3 = address(new ERC4626Target3(config, pool));
        address target4 = address(new ERC4626Target4(config, pool));
        mockHyperdrive = new MockERC4626Hyperdrive(
            config,
            target0,
            target1,
            target2,
            target3,
            target4,
            pool
        );

        vm.stopPrank();
        vm.startPrank(alice);
        factory.addDeployerCoordinator(deployerCoordinator);
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
        (uint256 sharesMinted, uint256 vaultSharePrice) = mockHyperdrive
            .deposit(
                1e18,
                IHyperdrive.Options({
                    destination: address(0),
                    asBase: true,
                    extraData: new bytes(0)
                })
            );
        assertEq(vaultSharePrice, 1.5e18);
        // 1/1.5 = 0.666666666666666666
        assertEq(sharesMinted, 666666666666666666);
        assertEq(pool.balanceOf(address(mockHyperdrive)), 666666666666666666);

        // Now we try to do a deposit from alice's shares
        pool.approve(address(mockHyperdrive), type(uint256).max);
        (sharesMinted, vaultSharePrice) = mockHyperdrive.deposit(
            3e18,
            IHyperdrive.Options({
                destination: address(0),
                asBase: false,
                extraData: new bytes(0)
            })
        );
        assertEq(vaultSharePrice, 1.5e18);
        assertEq(sharesMinted, 3e18);
        // 666666666666666666 shares + 3e18 shares = 3666666666666666666
        assertApproxEqAbs(
            pool.balanceOf(address(mockHyperdrive)),
            3666666666666666666,
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
        uint256 amountWithdrawn = mockHyperdrive.withdraw(
            2e18,
            mockHyperdrive.pricePerVaultShare(),
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );
        uint256 balanceAfter = dai.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore + 3e18);
        assertEq(amountWithdrawn, 3e18);

        // Test a share withdraw
        amountWithdrawn = mockHyperdrive.withdraw(
            2e18,
            mockHyperdrive.pricePerVaultShare(),
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: new bytes(0)
            })
        );
        assertEq(pool.balanceOf(alice), 2e18);
        assertEq(amountWithdrawn, 2e18);
    }

    function test_erc4626_withdraw_zero() external {
        // First we add some shares and interest.
        vm.startPrank(alice);
        dai.transfer(address(pool), 5e18);
        pool.transfer(address(mockHyperdrive), 10e18);
        uint256 balanceBefore = dai.balanceOf(alice);

        // Test an underlying withdraw of zero.
        uint256 amountWithdrawn = mockHyperdrive.withdraw(
            0,
            mockHyperdrive.pricePerVaultShare(),
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );
        uint256 balanceAfter = dai.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore);
        assertEq(amountWithdrawn, 0);

        // Test a share withdraw of zero.
        amountWithdrawn = mockHyperdrive.withdraw(
            0,
            mockHyperdrive.pricePerVaultShare(),
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: new bytes(0)
            })
        );
        assertEq(pool.balanceOf(alice), 0);
        assertEq(amountWithdrawn, 0);
    }

    function test_erc4626_testDeploy() external {
        vm.startPrank(alice);
        uint256 apr = 0.01e18; // 1% apr
        uint256 contribution = 2_500e18;
        IHyperdrive.PoolDeployConfig memory config = IHyperdrive
            .PoolDeployConfig({
                baseToken: dai,
                linkerFactory: factory.linkerFactory(),
                linkerCodeHash: factory.linkerCodeHash(),
                minimumShareReserves: ONE,
                minimumTransactionAmount: 0.001e18,
                positionDuration: 365 days,
                checkpointDuration: 1 days,
                timeStretch: HyperdriveMath.calculateTimeStretch(apr, 365 days),
                governance: factory.hyperdriveGovernance(),
                feeCollector: factory.feeCollector(),
                fees: IHyperdrive.Fees(0, 0, 0, 0)
            });
        dai.approve(address(factory), type(uint256).max);
        factory.deployTarget(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            config,
            abi.encode(address(pool)),
            apr,
            apr,
            0,
            bytes32(uint256(0xdeadbabe))
        );
        factory.deployTarget(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            config,
            abi.encode(address(pool)),
            apr,
            apr,
            1,
            bytes32(uint256(0xdeadbabe))
        );
        factory.deployTarget(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            config,
            abi.encode(address(pool)),
            apr,
            apr,
            2,
            bytes32(uint256(0xdeadbabe))
        );
        factory.deployTarget(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            config,
            abi.encode(address(pool)),
            apr,
            apr,
            3,
            bytes32(uint256(0xdeadbabe))
        );
        factory.deployTarget(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            config,
            abi.encode(address(pool)),
            apr,
            apr,
            4,
            bytes32(uint256(0xdeadbabe))
        );
        hyperdrive = factory.deployAndInitialize(
            bytes32(uint256(0xdeadbeef)),
            deployerCoordinator,
            config,
            abi.encode(address(pool)),
            contribution,
            apr,
            apr,
            new bytes(0),
            bytes32(uint256(0xdeadbabe))
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
            deployerCoordinator,
            hyperdrive,
            alice,
            contribution,
            apr,
            config.minimumShareReserves,
            abi.encode(address(pool)),
            0
        );
    }

    function test_erc4626_vaultSharePrice() public {
        // This test ensures that `getPoolInfo` returns the correct share price.
        vm.startPrank(alice);
        uint256 apr = 0.01e18; // 1% apr
        uint256 contribution = 2_500e18;
        IHyperdrive.PoolDeployConfig memory config = IHyperdrive
            .PoolDeployConfig({
                baseToken: dai,
                linkerFactory: factory.linkerFactory(),
                linkerCodeHash: factory.linkerCodeHash(),
                minimumShareReserves: ONE,
                minimumTransactionAmount: 0.001e18,
                positionDuration: 365 days,
                checkpointDuration: 1 days,
                timeStretch: HyperdriveMath.calculateTimeStretch(apr, 365 days),
                governance: factory.hyperdriveGovernance(),
                feeCollector: factory.feeCollector(),
                fees: IHyperdrive.Fees(0, 0, 0, 0)
            });
        dai.approve(address(factory), type(uint256).max);
        factory.deployTarget(
            bytes32(uint256(0xdead)),
            deployerCoordinator,
            config,
            abi.encode(address(pool)),
            apr,
            apr,
            0,
            bytes32(uint256(0xbabe))
        );
        factory.deployTarget(
            bytes32(uint256(0xdead)),
            deployerCoordinator,
            config,
            abi.encode(address(pool)),
            apr,
            apr,
            1,
            bytes32(uint256(0xbabe))
        );
        factory.deployTarget(
            bytes32(uint256(0xdead)),
            deployerCoordinator,
            config,
            abi.encode(address(pool)),
            apr,
            apr,
            2,
            bytes32(uint256(0xbabe))
        );
        factory.deployTarget(
            bytes32(uint256(0xdead)),
            deployerCoordinator,
            config,
            abi.encode(address(pool)),
            apr,
            apr,
            3,
            bytes32(uint256(0xbabe))
        );
        factory.deployTarget(
            bytes32(uint256(0xdead)),
            deployerCoordinator,
            config,
            abi.encode(address(pool)),
            apr,
            apr,
            4,
            bytes32(uint256(0xbabe))
        );
        hyperdrive = factory.deployAndInitialize(
            bytes32(uint256(0xdead)),
            deployerCoordinator,
            config,
            abi.encode(address(pool)),
            contribution,
            apr,
            apr,
            new bytes(0),
            bytes32(uint256(0xbabe))
        );

        // Ensure the share price is 1 after initialization.
        assertEq(hyperdrive.getPoolInfo().vaultSharePrice, 1e18);

        // Simulate interest accrual by sending funds to the pool.
        dai.transfer(address(pool), contribution);

        // Ensure that the share price calculations are correct when share price is not equal to 1e18.
        assertEq(
            hyperdrive.getPoolInfo().vaultSharePrice,
            (pool.totalAssets()).divDown(pool.totalSupply())
        );
    }
}
