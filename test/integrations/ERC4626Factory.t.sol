// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626HyperdriveFactory } from "contracts/src/factory/ERC4626HyperdriveFactory.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { ERC4626HyperdriveDeployer } from "contracts/src/instances/ERC4626HyperdriveDeployer.sol";
import { ERC4626Target0Deployer } from "contracts/src/instances/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "contracts/src/instances/ERC4626Target1Deployer.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { MockERC4626Hyperdrive } from "contracts/test/MockERC4626Hyperdrive.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract ERC4626FactoryBaseTest is HyperdriveTest {
    using FixedPointMath for *;

    ERC4626HyperdriveFactory factory;

    IERC20 dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));

    IERC4626 pool1;
    IERC4626 pool2;

    uint256 aliceShares;

    uint256 constant APR = 0.01e18; // 1% apr
    uint256 constant CONTRIBUTION = 2_500e18;

    IHyperdrive.PoolConfig config;

    function setUp() public virtual override __mainnet_fork(16_685_972) {
        alice = createUser("alice");
        bob = createUser("bob");

        vm.startPrank(deployer);

        // Deploy the ERC4626Hyperdrive factory and deployer.
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ForwarderFactory();
        factory = new ERC4626HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                fees: IHyperdrive.Fees(0, 0, 0),
                maxFees: IHyperdrive.Fees(0, 0, 0),
                defaultPausers: defaults,
                hyperdriveDeployer: new ERC4626HyperdriveDeployer(),
                target0Deployer: new ERC4626Target0Deployer(),
                target1Deployer: new ERC4626Target1Deployer(),
                linkerFactory: address(forwarderFactory),
                linkerCodeHash: forwarderFactory.ERC20LINK_HASH()
            }),
            new address[](0)
        );

        // Initialize this test's pool config.
        config = IHyperdrive.PoolConfig({
            baseToken: dai,
            initialSharePrice: 1e18,
            minimumShareReserves: 1e18,
            minimumTransactionAmount: 1e15,
            precisionThreshold: 1e14,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: HyperdriveUtils.calculateTimeStretch(APR),
            governance: alice,
            feeCollector: bob,
            fees: IHyperdrive.Fees(0, 0, 0),
            linkerFactory: address(forwarderFactory),
            linkerCodeHash: forwarderFactory.ERC20LINK_HASH()
        });

        vm.stopPrank();

        // Deploy yield sources
        pool1 = IERC4626(
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
        pool2 = IERC4626(
            address(
                new MockERC4626(
                    ERC20Mintable(address(dai)),
                    "savings dai",
                    "sDai",
                    0,
                    address(0),
                    false
                )
            )
        );

        // Start recording events.
        vm.recordLogs();
    }

    function _deployInstance(
        address deployerUser,
        address pool
    ) internal returns (IHyperdrive) {
        deal(address(dai), deployerUser, CONTRIBUTION);

        vm.startPrank(deployerUser);

        dai.approve(address(factory), CONTRIBUTION);

        IHyperdrive hyperdrive = factory.deployAndInitialize(
            config,
            CONTRIBUTION,
            APR,
            new bytes(0),
            new bytes32[](0),
            address(pool)
        );

        vm.stopPrank();

        return hyperdrive;
    }
}

contract ERC4626FactoryMultiDeployTest is ERC4626FactoryBaseTest {
    function test_erc4646FactoryDeploy_multiDeploy_multiPool() external {
        address charlie = createUser("charlie"); // External user 1
        address dan = createUser("dan"); // External user 2

        vm.startPrank(charlie);

        deal(address(dai), charlie, CONTRIBUTION);

        // 1. Charlie deploys factory with yDAI as yield source

        dai.approve(address(factory), CONTRIBUTION);

        assertEq(dai.balanceOf(charlie), CONTRIBUTION);
        assertEq(dai.balanceOf(address(pool1)), 0);

        IHyperdrive hyperdrive1 = factory.deployAndInitialize(
            config,
            CONTRIBUTION,
            APR,
            new bytes(0),
            new bytes32[](0),
            address(pool1)
        );

        assertEq(dai.balanceOf(charlie), 0);
        assertEq(dai.balanceOf(address(pool1)), CONTRIBUTION);

        // The initial price per share is one so the LP shares will initially
        // be worth one base. Alice should receive LP shares equaling her
        // contribution minus the shares that she set aside for the minimum
        // share reserves and the zero address's initial LP contribution.
        assertEq(
            hyperdrive1.balanceOf(AssetId._LP_ASSET_ID, charlie),
            CONTRIBUTION - 2 * config.minimumShareReserves
        );

        // Verify that the correct events were emitted.
        verifyFactoryEvents(
            factory,
            hyperdrive1,
            charlie,
            CONTRIBUTION,
            APR,
            config.minimumShareReserves,
            new bytes32[](0),
            0
        );

        assertEq(factory.getNumberOfInstances(), 1);
        assertEq(factory.getInstanceAtIndex(0), address(hyperdrive1));

        address[] memory instances = factory.getInstancesInRange(0, 0);
        assertEq(instances.length, 1);
        assertEq(instances[0], address(hyperdrive1));

        // 2. Charlie deploys factory with sDAI as yield source.

        deal(address(dai), charlie, CONTRIBUTION);

        dai.approve(address(factory), CONTRIBUTION);

        IHyperdrive hyperdrive2 = factory.deployAndInitialize(
            config,
            CONTRIBUTION,
            APR,
            new bytes(0),
            new bytes32[](0),
            address(pool2)
        );

        assertEq(dai.balanceOf(charlie), 0);
        assertEq(dai.balanceOf(address(pool2)), CONTRIBUTION);

        // The initial price per share is one so the LP shares will initially
        // be worth one base. Alice should receive LP shares equaling her
        // contribution minus the shares that she set aside for the minimum
        // share reserves and the zero address's initial LP contribution.
        assertEq(
            hyperdrive2.balanceOf(AssetId._LP_ASSET_ID, charlie),
            CONTRIBUTION - 2 * config.minimumShareReserves
        );

        // Verify that the correct events were emitted.
        verifyFactoryEvents(
            factory,
            hyperdrive2,
            charlie,
            CONTRIBUTION,
            APR,
            config.minimumShareReserves,
            new bytes32[](0),
            0
        );

        assertEq(factory.getNumberOfInstances(), 2);
        assertEq(factory.getInstanceAtIndex(0), address(hyperdrive1));
        assertEq(factory.getInstanceAtIndex(1), address(hyperdrive2));

        instances = factory.getInstancesInRange(0, 1);
        assertEq(instances.length, 2);
        assertEq(instances[0], address(hyperdrive1));
        assertEq(instances[1], address(hyperdrive2));

        // 3. Dan deploys factory with sDAI as yield source.

        deal(address(dai), dan, CONTRIBUTION);

        vm.startPrank(dan);

        dai.approve(address(factory), CONTRIBUTION);

        assertEq(dai.balanceOf(dan), CONTRIBUTION);
        assertEq(dai.balanceOf(address(pool2)), CONTRIBUTION); // From Charlie

        IHyperdrive hyperdrive3 = factory.deployAndInitialize(
            config,
            CONTRIBUTION,
            APR,
            new bytes(0),
            new bytes32[](0),
            address(pool2)
        );

        assertEq(dai.balanceOf(dan), 0);
        assertEq(dai.balanceOf(address(pool2)), CONTRIBUTION * 2);

        // The initial price per share is one so the LP shares will initially
        // be worth one base. Alice should receive LP shares equaling her
        // contribution minus the shares that she set aside for the minimum
        // share reserves and the zero address's initial LP contribution.
        assertEq(
            hyperdrive3.balanceOf(AssetId._LP_ASSET_ID, dan),
            CONTRIBUTION - 2 * config.minimumShareReserves
        );

        // Verify that the correct events were emitted.
        verifyFactoryEvents(
            factory,
            hyperdrive3,
            dan,
            CONTRIBUTION,
            APR,
            config.minimumShareReserves,
            new bytes32[](0),
            0
        );

        assertEq(factory.getNumberOfInstances(), 3);
        assertEq(factory.getInstanceAtIndex(0), address(hyperdrive1));
        assertEq(factory.getInstanceAtIndex(1), address(hyperdrive2));
        assertEq(factory.getInstanceAtIndex(2), address(hyperdrive3));

        instances = factory.getInstancesInRange(0, 2);
        assertEq(instances.length, 3);
        assertEq(instances[0], address(hyperdrive1));
        assertEq(instances[1], address(hyperdrive2));
        assertEq(instances[2], address(hyperdrive3));
    }
}

contract ERC4626InstanceGetterTest is ERC4626FactoryBaseTest {
    function testFuzz_erc4646Factory_getNumberOfInstances(
        uint256 numberOfInstances
    ) external {
        address charlie = createUser("charlie");

        numberOfInstances = _bound(numberOfInstances, 1, 10);

        for (uint256 i; i < numberOfInstances; i++) {
            _deployInstance(charlie, address(pool1));
        }

        assertEq(factory.getNumberOfInstances(), numberOfInstances);
    }

    function testFuzz_erc4646Factory_getInstanceAtIndex(
        uint256 numberOfInstances
    ) external {
        address charlie = createUser("charlie");

        numberOfInstances = _bound(numberOfInstances, 1, 10);

        IHyperdrive[] memory hyperdrives = new IHyperdrive[](numberOfInstances);

        for (uint256 i; i < numberOfInstances; i++) {
            hyperdrives[i] = _deployInstance(charlie, address(pool1));
        }

        for (uint256 i; i < numberOfInstances; i++) {
            assertEq(factory.getInstanceAtIndex(i), address(hyperdrives[i]));
        }
    }

    function testFuzz_erc4626Factory_getInstancesInRange(
        uint256 numberOfInstances,
        uint256 startingIndex,
        uint256 endingIndex
    ) external {
        address charlie = createUser("charlie");

        numberOfInstances = _bound(numberOfInstances, 1, 10);
        startingIndex = _bound(startingIndex, 0, numberOfInstances - 1);
        endingIndex = _bound(endingIndex, startingIndex, numberOfInstances - 1);

        IHyperdrive[] memory hyperdrives = new IHyperdrive[](numberOfInstances);

        for (uint256 i; i < numberOfInstances; i++) {
            hyperdrives[i] = _deployInstance(charlie, address(pool1));
        }

        address[] memory instances = factory.getInstancesInRange(
            startingIndex,
            endingIndex
        );

        assertEq(instances.length, endingIndex - startingIndex + 1);

        for (uint256 i; i < instances.length; i++) {
            assertEq(instances[i], address(hyperdrives[i + startingIndex]));
        }
    }
}
