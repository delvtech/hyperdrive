// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { VmSafe } from "forge-std/Vm.sol";
import { ERC4626HyperdriveCoreDeployer } from "../../../contracts/src/deployers/erc4626/ERC4626HyperdriveCoreDeployer.sol";
import { ERC4626HyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/erc4626/ERC4626HyperdriveDeployerCoordinator.sol";
import { ERC4626Target0Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target1Deployer.sol";
import { ERC4626Target2Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target2Deployer.sol";
import { ERC4626Target3Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target3Deployer.sol";
import { ERC4626Target4Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target4Deployer.sol";
import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../../contracts/src/interfaces/IHyperdriveDeployerCoordinator.sol";
import { IHyperdriveFactory } from "../../../contracts/src/interfaces/IHyperdriveFactory.sol";
import { IHyperdriveGovernedRegistry } from "../../../contracts/src/interfaces/IHyperdriveGovernedRegistry.sol";
import { IHyperdriveGovernedRegistryEvents } from "../../../contracts/src/interfaces/IHyperdriveGovernedRegistryEvents.sol";
import { IHyperdriveRegistry } from "../../../contracts/src/interfaces/IHyperdriveRegistry.sol";
import { VERSION } from "../../../contracts/src/libraries/Constants.sol";
import { ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveRegistry } from "../../../contracts/src/registry/HyperdriveRegistry.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "../../../contracts/test/MockERC4626.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract HyperdriveRegistryTest is
    HyperdriveTest,
    IHyperdriveGovernedRegistryEvents
{
    using Lib for *;

    string internal constant HYPERDRIVE_NAME = "Hyperdrive";
    string internal constant COORDINATOR_NAME = "HyperdriveDeployerCoordinator";
    string internal constant REGISTRY_NAME = "HyperdriveRegistry";
    uint256 internal constant FIXED_RATE = 0.05e18;

    IERC4626 internal vaultSharesToken;

    function setUp() public override {
        // Run HyperdriveTests's setUp.
        super.setUp();

        // Instantiate the Hyperdrive registry. This ensures that we are testing
        // against a fresh state.
        registry = new HyperdriveRegistry();
        registry.initialize(REGISTRY_NAME, registrar);

        // Deploy a base token.
        baseToken = new ERC20Mintable(
            "Base",
            "BASE",
            18,
            address(0),
            false,
            type(uint256).max
        );

        // Deploy a mock yield source.
        vaultSharesToken = IERC4626(
            address(
                new MockERC4626(
                    baseToken,
                    "Vault",
                    "VAULT",
                    0,
                    address(0),
                    false,
                    type(uint256).max
                )
            )
        );

        // Start recording event logs.
        vm.recordLogs();
    }

    /// Helpers ///

    function deployFactory() internal returns (IHyperdriveFactory, address) {
        // Deploy the factory.
        IHyperdriveFactory factory = IHyperdriveFactory(
            address(
                new HyperdriveFactory(
                    HyperdriveFactory.FactoryConfig({
                        governance: alice,
                        deployerCoordinatorManager: celine,
                        hyperdriveGovernance: bob,
                        feeCollector: feeCollector,
                        sweepCollector: sweepCollector,
                        checkpointRewarder: address(checkpointRewarder),
                        defaultPausers: new address[](0),
                        checkpointDurationResolution: 1 hours,
                        minCheckpointDuration: 8 hours,
                        maxCheckpointDuration: 1 days,
                        minPositionDuration: 7 days,
                        maxPositionDuration: 10 * 365 days,
                        minCircuitBreakerDelta: 0.15e18,
                        // NOTE: This is a high max circuit breaker delta to ensure that
                        // trading during tests isn't impeded by the circuit breaker.
                        maxCircuitBreakerDelta: 2e18,
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
                    }),
                    "HyperdriveFactory"
                )
            )
        );

        // Deploy an ERC4626 hyperdrive deployer coordinator and register it
        // within the factory.
        vm.stopPrank();
        vm.startPrank(factory.deployerCoordinatorManager());
        address coreDeployer = address(new ERC4626HyperdriveCoreDeployer());
        address target0Deployer = address(new ERC4626Target0Deployer());
        address target1Deployer = address(new ERC4626Target1Deployer());
        address target2Deployer = address(new ERC4626Target2Deployer());
        address target3Deployer = address(new ERC4626Target3Deployer());
        address target4Deployer = address(new ERC4626Target4Deployer());
        address deployerCoordinator = address(
            new ERC4626HyperdriveDeployerCoordinator(
                COORDINATOR_NAME,
                address(factory),
                coreDeployer,
                target0Deployer,
                target1Deployer,
                target2Deployer,
                target3Deployer,
                target4Deployer
            )
        );
        factory.addDeployerCoordinator(deployerCoordinator);

        return (factory, deployerCoordinator);
    }

    function deployInstance(
        IHyperdriveFactory _factory,
        address _deployerCoordinator,
        uint256 _seed
    ) internal returns (IHyperdrive) {
        IHyperdrive.PoolDeployConfig memory config = testDeployConfig(
            FIXED_RATE,
            POSITION_DURATION
        );
        config.timeStretch = 0;
        config.governance = _factory.hyperdriveGovernance();
        config.linkerFactory = _factory.linkerFactory();
        config.linkerCodeHash = _factory.linkerCodeHash();
        config.feeCollector = _factory.feeCollector();
        config.sweepCollector = _factory.sweepCollector();
        config.checkpointRewarder = _factory.checkpointRewarder();
        config.vaultSharesToken = vaultSharesToken;
        for (
            uint256 i = 0;
            i <
            IHyperdriveDeployerCoordinator(_deployerCoordinator)
                .getNumberOfTargets();
            i++
        ) {
            _factory.deployTarget(
                bytes32(_seed),
                _deployerCoordinator,
                config,
                new bytes(0),
                FIXED_RATE,
                FIXED_RATE,
                i,
                bytes32(_seed)
            );
        }
        uint256 contribution = 100_000e18;
        baseToken.mint(contribution);
        baseToken.approve(_deployerCoordinator, contribution);
        return
            _factory.deployAndInitialize(
                bytes32(_seed),
                _deployerCoordinator,
                HYPERDRIVE_NAME,
                config,
                new bytes(0),
                contribution,
                FIXED_RATE,
                FIXED_RATE,
                IHyperdrive.Options({
                    asBase: true,
                    destination: alice,
                    extraData: new bytes(0)
                }),
                bytes32(_seed)
            );
    }

    /// Tests ///

    function test_name() public view {
        assertEq(registry.name(), REGISTRY_NAME);
    }

    function test_kind() public view {
        assertEq(registry.kind(), "HyperdriveRegistry");
    }

    function test_version() public view {
        assertEq(registry.version(), VERSION);
    }

    function test_initialize_failure_alreadyInitialized() public {
        // Ensure that the registry can't be initialized again.
        vm.expectRevert(
            IHyperdriveGovernedRegistry.RegistryAlreadyInitialized.selector
        );
        registry.initialize(REGISTRY_NAME, alice);
    }

    function test_initialize() public {
        registry = new HyperdriveRegistry();

        // Ensure that the correct event is emitted and that the state is
        // updated propery when the registry is initialized.
        address admin = alice;
        vm.expectEmit(true, true, true, true);
        emit Initialized(REGISTRY_NAME, admin);
        registry.initialize(REGISTRY_NAME, admin);
        assertTrue(registry.isInitialized());
        assertTrue(registry.name().eq(REGISTRY_NAME));
        assertEq(registry.admin(), admin);
    }

    function test_updateAdmin_failure_onlyAdmin() public {
        address notAdmin = makeAddr("notAdmin");

        // Ensure that an address that isn't the admin can't update the admin.
        vm.stopPrank();
        vm.startPrank(notAdmin);
        vm.expectRevert(IHyperdriveGovernedRegistry.Unauthorized.selector);
        registry.updateAdmin(notAdmin);
    }

    function test_updateAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        // Ensure that the registry's admin can update the admin address.
        vm.stopPrank();
        vm.startPrank(registry.admin());
        vm.expectEmit(true, true, true, true);
        emit AdminUpdated(newAdmin);
        registry.updateAdmin(newAdmin);
        assertEq(registry.admin(), newAdmin);
    }

    function test_updateName_failure_onlyAdmin() public {
        address notAdmin = makeAddr("notAdmin");
        string memory newName = "New Registry Name";

        // Ensure that an address that isn't the admin can't update the name.
        vm.stopPrank();
        vm.startPrank(notAdmin);
        vm.expectRevert(IHyperdriveGovernedRegistry.Unauthorized.selector);
        registry.updateName(newName);
    }

    function test_updateName() public {
        string memory newName = "New Registry Name";

        // Ensure that the registry's admin can update the name.
        vm.stopPrank();
        vm.startPrank(registry.admin());
        vm.expectEmit(true, true, true, true);
        emit NameUpdated(newName);
        registry.updateName(newName);
        assertTrue(registry.name().eq(newName));
    }

    function test_setFactoryInfo_failure_onlyAdmin() public {
        // Deploy a factory.
        address notAdmin = makeAddr("notAdmin");
        (IHyperdriveFactory factory, ) = deployFactory();

        // Ensure that `setFactoryInfo` can't be called by an address that
        // isn't the admin.
        vm.stopPrank();
        vm.startPrank(notAdmin);
        address[] memory factories = new address[](1);
        uint128[] memory data = new uint128[](1);
        factories[0] = address(factory);
        data[0] = 1;
        vm.expectRevert(IHyperdriveGovernedRegistry.Unauthorized.selector);
        registry.setFactoryInfo(factories, data);
    }

    function test_setFactoryInfo_failure_inputLengthMismatch() public {
        // Deploy a factory.
        (IHyperdriveFactory factory, ) = deployFactory();

        // Ensure that adding a factory fails when then factories list is
        // longer than the data list.
        vm.stopPrank();
        vm.startPrank(registry.admin());
        address[] memory factories = new address[](1);
        uint128[] memory data = new uint128[](0);
        factories[0] = address(factory);
        vm.expectRevert(
            IHyperdriveGovernedRegistry.InputLengthMismatch.selector
        );
        registry.setFactoryInfo(factories, data);
    }

    function test_setFactoryInfo_success_addSingleFactory() public {
        // Deploy a factory.
        (IHyperdriveFactory factory, ) = deployFactory();

        // Ensure that the new factory is registered correctly.
        address[] memory factories = new address[](1);
        uint128[] memory data = new uint128[](1);
        factories[0] = address(factory);
        data[0] = 1;
        ensureAddFactoryInfo(factories, data);
    }

    function test_setFactoryInfo_success_addSingleFactoryTwice() public {
        // Deploy two factories.
        (IHyperdriveFactory factory0, ) = deployFactory();
        (IHyperdriveFactory factory1, ) = deployFactory();

        // Ensure that the first factory is registered correctly.
        address[] memory factories = new address[](1);
        uint128[] memory data = new uint128[](1);
        factories[0] = address(factory0);
        data[0] = 1;
        ensureAddFactoryInfo(factories, data);

        // Ensure that the second factory is registered correctly.
        factories[0] = address(factory1);
        ensureAddFactoryInfo(factories, data);
    }

    function test_setFactoryInfo_success_addMultipleFactories() public {
        // Deploy several factories.
        uint256 factoryCount = 3;
        address[] memory factories = new address[](factoryCount);
        uint128[] memory data = new uint128[](factoryCount);
        for (uint256 i = 0; i < factoryCount; i++) {
            (IHyperdriveFactory factory, ) = deployFactory();
            factories[i] = address(factory);
            data[i] = 1;
        }

        // Ensure that the factories are registered correctly.
        ensureAddFactoryInfo(factories, data);
    }

    function test_setFactoryInfo_success_updateSingleFactory() public {
        // Deploy a factory.
        (IHyperdriveFactory factory, ) = deployFactory();

        // Register the factory.
        address[] memory factories = new address[](1);
        uint128[] memory data = new uint128[](1);
        factories[0] = address(factory);
        data[0] = 1;
        ensureAddFactoryInfo(factories, data);

        // Update the factory.
        data[0] = 2;
        ensureUpdateFactoryInfo(factories, data);
    }

    function test_setFactoryInfo_success_updateMultipleFactories() public {
        // Deploy several factories.
        uint256 factoryCount = 7;
        address[] memory factories = new address[](factoryCount);
        uint128[] memory data = new uint128[](factoryCount);
        for (uint256 i = 0; i < factoryCount; i++) {
            (IHyperdriveFactory factory, ) = deployFactory();
            factories[i] = address(factory);
            data[i] = 1;
        }

        // Register the new factories.
        ensureAddFactoryInfo(factories, data);

        // Ensure the factories are updated correctly.
        for (uint256 i = 0; i < factoryCount; i++) {
            data[i] = uint128(i + 1);
        }
        ensureUpdateFactoryInfo(factories, data);
    }

    function test_setFactoryInfo_success_removeSingleFactory() public {
        // Deploy a factory.
        (IHyperdriveFactory factory, ) = deployFactory();

        // Register the factory.
        address[] memory factories = new address[](1);
        uint128[] memory data = new uint128[](1);
        factories[0] = address(factory);
        data[0] = 1;
        ensureAddFactoryInfo(factories, data);

        // Ensure that the factory is successfully removed.
        ensureRemoveFactoryInfo(factories);
    }

    function test_setFactoryInfo_success_removeNonexistentFactory() public {
        // Deploy a factory.
        (IHyperdriveFactory factory, ) = deployFactory();

        // Ensure that a nonexistent factory can be successfully removed (with
        // no effect).
        address[] memory factories = new address[](1);
        uint128[] memory data = new uint128[](1);
        factories[0] = address(factory);
        data[0] = 0;
        vm.stopPrank();
        vm.startPrank(registry.admin());
        registry.setFactoryInfo(factories, data);

        // Ensure that the list wasn't updated and that the mapping wasn't
        // updated.
        assertEq(registry.getNumberOfFactories(), 0);
        IHyperdriveRegistry.FactoryInfo[] memory info = registry
            .getFactoryInfos(factories);
        assertEq(info[0].data, 0);

        // Ensure that no events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            FactoryInfoUpdated.selector
        );
        assertEq(logs.length, 0);
    }

    function test_setFactoryInfo_success_removeMultipleFactories() public {
        // Deploy several factories.
        uint256 factoryCount = 4;
        address[] memory factories = new address[](factoryCount);
        uint128[] memory data = new uint128[](factoryCount);
        for (uint256 i = 0; i < factoryCount; i++) {
            (IHyperdriveFactory factory, ) = deployFactory();
            factories[i] = address(factory);
            data[i] = 1;
        }

        // Registered the new factories.
        ensureAddFactoryInfo(factories, data);

        // Removed the factories.
        ensureRemoveFactoryInfo(factories);
    }

    function test_setFactoryInfo_success_mixed() public {
        // Deploy several factories.
        uint256 factoryCount = 4;
        address[] memory factories = new address[](factoryCount);
        for (uint256 i = 0; i < factoryCount; i++) {
            (IHyperdriveFactory factory, ) = deployFactory();
            factories[i] = address(factory);
        }

        // Register three of the factories.
        address[] memory addedFactories = new address[](factoryCount - 1);
        uint128[] memory addedData = new uint128[](factoryCount - 1);
        for (uint256 i = 0; i < factoryCount - 1; i++) {
            addedFactories[i] = factories[i];
            addedData[i] = 1;
        }
        ensureAddFactoryInfo(addedFactories, addedData);

        // Mix and match updating the registry. The first entry is removed, the
        // second and third are updated, and the last is added.
        uint128[] memory data = new uint128[](factoryCount);
        data[0] = 0;
        data[1] = 2;
        data[2] = 2;
        data[3] = 1;
        registry.setFactoryInfo(factories, data);

        // Ensure that the entries were updated properly in the registry.
        assertEq(registry.getNumberOfFactories(), factoryCount - 1);
        assertEq(registry.getFactoryAtIndex(0), factories[2]);
        assertEq(registry.getFactoryAtIndex(1), factories[1]);
        assertEq(registry.getFactoryAtIndex(2), factories[3]);
        IHyperdriveRegistry.FactoryInfo[] memory info = registry
            .getFactoryInfos(factories);
        for (uint256 i = 0; i < factories.length; i++) {
            assertEq(info[i].data, data[i]);
        }

        // Verify that the correct events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            FactoryInfoUpdated.selector
        );
        assertEq(logs.length, factories.length);
        for (uint256 i = 0; i < factories.length; i++) {
            VmSafe.Log memory log = logs[i];
            assertEq(address(uint160(uint256(log.topics[1]))), factories[i]);
            assertEq(uint128(uint256(log.topics[2])), data[i]);
        }
    }

    function test_setInstanceInfo_failure_onlyAdmin() public {
        // Deploy a factory and an instance.
        address notAdmin = makeAddr("notAdmin");
        (
            IHyperdriveFactory factory,
            address deployerCoordinator
        ) = deployFactory();
        IHyperdrive instance = deployInstance(factory, deployerCoordinator, 0);

        // Ensure that `setInstanceInfo` can't be called by an address that isn't
        // the admin.
        vm.stopPrank();
        vm.startPrank(notAdmin);
        address[] memory instances = new address[](1);
        uint128[] memory data = new uint128[](1);
        address[] memory factories = new address[](1);
        instances[0] = address(instance);
        data[0] = 1;
        factories[0] = address(factory);
        vm.expectRevert(IHyperdriveGovernedRegistry.Unauthorized.selector);
        registry.setInstanceInfo(instances, data, factories);
    }

    function test_setInstanceInfo_failure_inputLengthMismatch() public {
        // Deploy a factory and an instance.
        (
            IHyperdriveFactory factory,
            address deployerCoordinator
        ) = deployFactory();
        IHyperdrive instance = deployInstance(factory, deployerCoordinator, 0);

        // Ensure that adding an instance fails when then instances list is
        // longer than the data list.
        {
            address[] memory instances = new address[](1);
            uint128[] memory data = new uint128[](0);
            address[] memory factories = new address[](1);
            instances[0] = address(instance);
            factories[0] = address(factory);
            vm.stopPrank();
            vm.startPrank(registry.admin());
            vm.expectRevert(
                IHyperdriveGovernedRegistry.InputLengthMismatch.selector
            );
            registry.setInstanceInfo(instances, data, factories);
        }

        // Ensure that adding an instance fails when then instances list is
        // longer than the factories list.
        {
            address[] memory instances = new address[](1);
            uint128[] memory data = new uint128[](1);
            address[] memory factories = new address[](0);
            instances[0] = address(instance);
            data[0] = 1;
            vm.stopPrank();
            vm.startPrank(registry.admin());
            vm.expectRevert(
                IHyperdriveGovernedRegistry.InputLengthMismatch.selector
            );
            registry.setInstanceInfo(instances, data, factories);
        }
    }

    function test_setInstanceInfo_failure_addWithInvalidFactory() public {
        // Deploy a factory and an instance. Then deploy a separate factory.
        (
            IHyperdriveFactory factory,
            address deployerCoordinator
        ) = deployFactory();
        IHyperdrive instance = deployInstance(factory, deployerCoordinator, 0);
        (IHyperdriveFactory otherFactory, ) = deployFactory();

        // Ensure that adding an instance fails when the factory address is
        // invalid.
        address[] memory instances = new address[](1);
        uint128[] memory data = new uint128[](1);
        address[] memory factories = new address[](1);
        instances[0] = address(instance);
        data[0] = 1;
        factories[0] = address(otherFactory);
        vm.stopPrank();
        vm.startPrank(registry.admin());
        vm.expectRevert(IHyperdriveGovernedRegistry.InvalidFactory.selector);
        registry.setInstanceInfo(instances, data, factories);
    }

    function test_setInstanceInfo_success_addSingleInstance() public {
        // Deploy a factory and an instance.
        (
            IHyperdriveFactory factory,
            address deployerCoordinator
        ) = deployFactory();
        IHyperdrive instance = deployInstance(factory, deployerCoordinator, 0);

        // Ensure that the new instance is registered correctly.
        address[] memory instances = new address[](1);
        uint128[] memory data = new uint128[](1);
        address[] memory factories = new address[](1);
        instances[0] = address(instance);
        data[0] = 1;
        factories[0] = address(factory);
        ensureAddInstanceInfo(instances, data, factories);
    }

    function test_setInstanceInfo_success_addSingleInstanceWithoutFactory()
        public
    {
        // Deploy a factory and an instance.
        (
            IHyperdriveFactory factory,
            address deployerCoordinator
        ) = deployFactory();
        IHyperdrive instance = deployInstance(factory, deployerCoordinator, 0);

        // Ensure that the new instance is registered correctly.
        address[] memory instances = new address[](1);
        uint128[] memory data = new uint128[](1);
        address[] memory factories = new address[](1);
        instances[0] = address(instance);
        data[0] = 1;
        factories[0] = address(0);
        ensureAddInstanceInfo(instances, data, factories);
    }

    function test_setInstanceInfo_success_addSingleInstanceTwice() public {
        // Deploy a factory and two instances.
        (
            IHyperdriveFactory factory,
            address deployerCoordinator
        ) = deployFactory();
        IHyperdrive instance0 = deployInstance(factory, deployerCoordinator, 0);
        IHyperdrive instance1 = deployInstance(factory, deployerCoordinator, 1);

        // Ensure that the first instance is registered correctly.
        address[] memory instances = new address[](1);
        uint128[] memory data = new uint128[](1);
        address[] memory factories = new address[](1);
        instances[0] = address(instance0);
        data[0] = 1;
        factories[0] = address(factory);
        ensureAddInstanceInfo(instances, data, factories);

        // Ensure that the second instance is registered correctly.
        instances = new address[](1);
        data = new uint128[](1);
        factories = new address[](1);
        instances[0] = address(instance1);
        data[0] = 1;
        factories[0] = address(factory);
        ensureAddInstanceInfo(instances, data, factories);
    }

    function test_setInstanceInfo_success_addMultipleInstances() public {
        // Deploy several factories and instances.
        uint256 instanceCount = 3;
        address[] memory instances = new address[](instanceCount);
        uint128[] memory data = new uint128[](instanceCount);
        address[] memory factories = new address[](instanceCount);
        for (uint256 i = 0; i < instanceCount; i++) {
            (
                IHyperdriveFactory factory,
                address deployerCoordinator
            ) = deployFactory();
            IHyperdrive instance = deployInstance(
                factory,
                deployerCoordinator,
                0
            );
            instances[i] = address(instance);
            data[i] = 1;
            factories[i] = address(factory);
        }

        // Ensure that the instances are registered correctly.
        ensureAddInstanceInfo(instances, data, factories);
    }

    function test_setInstanceInfo_failure_updateInvalidFactory() public {
        // Deploy a factory and an instance.
        (
            IHyperdriveFactory factory,
            address deployerCoordinator
        ) = deployFactory();
        IHyperdrive instance = deployInstance(factory, deployerCoordinator, 0);

        // Register the new instance.
        address[] memory instances = new address[](1);
        uint128[] memory data = new uint128[](1);
        address[] memory factories = new address[](1);
        instances[0] = address(instance);
        data[0] = 1;
        factories[0] = address(factory);
        vm.stopPrank();
        vm.startPrank(registry.admin());
        registry.setInstanceInfo(instances, data, factories);

        // Ensure that the instance that had a non-zero factory can't be updated
        // with a zero factory.
        data[0] = 2;
        factories[0] = address(0);
        vm.stopPrank();
        vm.startPrank(registry.admin());
        vm.expectRevert(IHyperdriveGovernedRegistry.InvalidFactory.selector);
        registry.setInstanceInfo(instances, data, factories);

        // Ensure that the instance can't be updated with an invalid factory.
        data[0] = 2;
        factories[0] = address(0xdeadbeef);
        vm.stopPrank();
        vm.startPrank(registry.admin());
        vm.expectRevert(IHyperdriveGovernedRegistry.InvalidFactory.selector);
        registry.setInstanceInfo(instances, data, factories);
    }

    function test_setInstanceInfo_success_updateSingleInstance() public {
        // Deploy a factory and an instance.
        (
            IHyperdriveFactory factory,
            address deployerCoordinator
        ) = deployFactory();
        IHyperdrive instance = deployInstance(factory, deployerCoordinator, 0);

        // Register the instance.
        address[] memory instances = new address[](1);
        uint128[] memory data = new uint128[](1);
        address[] memory factories = new address[](1);
        instances[0] = address(instance);
        data[0] = 1;
        factories[0] = address(factory);
        ensureAddInstanceInfo(instances, data, factories);

        // Update the instance.
        data[0] = 2;
        ensureUpdateInstanceInfo(instances, data, factories);
    }

    function test_setInstanceInfo_success_updateSingleInstanceWithFactory()
        public
    {
        // Deploy a factory and an instance.
        (
            IHyperdriveFactory factory,
            address deployerCoordinator
        ) = deployFactory();
        IHyperdrive instance = deployInstance(factory, deployerCoordinator, 0);

        // Register the instance with a factory address of zero.
        address[] memory instances = new address[](1);
        uint128[] memory data = new uint128[](1);
        address[] memory factories = new address[](1);
        instances[0] = address(instance);
        data[0] = 1;
        factories[0] = address(0);
        ensureAddInstanceInfo(instances, data, factories);

        // Update the instance with a non-zero factory address.
        data[0] = 2;
        factories[0] = address(factory);
        ensureUpdateInstanceInfo(instances, data, factories);
    }

    function test_setInstanceInfo_success_updateMultipleInstances() public {
        // Deploy several factories and instances.
        uint256 instanceCount = 7;
        address[] memory instances = new address[](instanceCount);
        uint128[] memory data = new uint128[](instanceCount);
        address[] memory factories = new address[](instanceCount);
        for (uint256 i = 0; i < instanceCount; i++) {
            (
                IHyperdriveFactory factory,
                address deployerCoordinator
            ) = deployFactory();
            IHyperdrive instance = deployInstance(
                factory,
                deployerCoordinator,
                0
            );
            instances[i] = address(instance);
            data[i] = 1;
            factories[i] = address(factory);
        }

        // Register the new instances.
        ensureAddInstanceInfo(instances, data, factories);

        // Update the instances.
        for (uint256 i = 0; i < instanceCount; i++) {
            data[i] = uint128(i + 1);
        }
        ensureUpdateInstanceInfo(instances, data, factories);
    }

    function test_setInstanceInfo_failure_removeNonzeroFactory() public {
        // Deploy a factory and an instance.
        (
            IHyperdriveFactory factory,
            address deployerCoordinator
        ) = deployFactory();
        IHyperdrive instance = deployInstance(factory, deployerCoordinator, 0);

        // Register the instance.
        address[] memory instances = new address[](1);
        uint128[] memory data = new uint128[](1);
        address[] memory factories = new address[](1);
        instances[0] = address(instance);
        data[0] = 1;
        factories[0] = address(factory);
        ensureAddInstanceInfo(instances, data, factories);

        // Ensure that the instance can't be removed with a non-zero factory.
        data[0] = 0;
        vm.stopPrank();
        vm.startPrank(registry.admin());
        vm.expectRevert(IHyperdriveGovernedRegistry.InvalidFactory.selector);
        registry.setInstanceInfo(instances, data, factories);
    }

    function test_setInstanceInfo_success_removeSingleInstance() public {
        // Deploy a factory and an instance.
        (
            IHyperdriveFactory factory,
            address deployerCoordinator
        ) = deployFactory();
        IHyperdrive instance = deployInstance(factory, deployerCoordinator, 0);

        // Register the instance.
        address[] memory instances = new address[](1);
        uint128[] memory data = new uint128[](1);
        address[] memory factories = new address[](1);
        instances[0] = address(instance);
        data[0] = 1;
        factories[0] = address(factory);
        ensureAddInstanceInfo(instances, data, factories);

        // Ensure that the instance is successfully removed.
        ensureRemoveInstanceInfo(instances);
    }

    function test_setInstanceInfo_success_removeNonexistentInstance() public {
        // Deploy a factory and an instance.
        (
            IHyperdriveFactory factory,
            address deployerCoordinator
        ) = deployFactory();
        IHyperdrive instance = deployInstance(factory, deployerCoordinator, 0);

        // Ensure that a nonexistent instance can be successfully removed (with
        // no effect).
        address[] memory instances = new address[](1);
        uint128[] memory data = new uint128[](1);
        address[] memory factories = new address[](1);
        instances[0] = address(instance);
        data[0] = 0;
        factories[0] = address(0);
        vm.stopPrank();
        vm.startPrank(registry.admin());
        registry.setInstanceInfo(instances, data, factories);

        // Ensure that the list wasn't updated and that the mapping wasn't
        // updated.
        assertEq(registry.getNumberOfInstances(), 0);
        IHyperdriveRegistry.InstanceInfo[] memory info = registry
            .getInstanceInfos(instances);
        assertEq(info[0].data, 0);
        assertEq(info[0].factory, address(0));

        // Ensure that no events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            InstanceInfoUpdated.selector
        );
        assertEq(logs.length, 0);
    }

    function test_setInstanceInfo_success_removeMultipleInstances() public {
        // Deploy several factories and instances.
        uint256 instanceCount = 4;
        address[] memory instances = new address[](instanceCount);
        uint128[] memory data = new uint128[](instanceCount);
        address[] memory factories = new address[](instanceCount);
        for (uint256 i = 0; i < instanceCount; i++) {
            (
                IHyperdriveFactory factory,
                address deployerCoordinator
            ) = deployFactory();
            IHyperdrive instance = deployInstance(
                factory,
                deployerCoordinator,
                0
            );
            instances[i] = address(instance);
            data[i] = 1;
            factories[i] = address(factory);
        }

        // Registered the new instances.
        ensureAddInstanceInfo(instances, data, factories);

        // Removed the instances.
        ensureRemoveInstanceInfo(instances);
    }

    function test_setInstanceInfo_success_mixed() public {
        // Deploy several factories and instances.
        uint256 instanceCount = 4;
        address[] memory instances = new address[](instanceCount);
        address[] memory factories = new address[](instanceCount);
        for (uint256 i = 0; i < instanceCount; i++) {
            (
                IHyperdriveFactory factory,
                address deployerCoordinator
            ) = deployFactory();
            IHyperdrive instance = deployInstance(
                factory,
                deployerCoordinator,
                0
            );
            instances[i] = address(instance);
            factories[i] = address(factory);
        }

        // Register three of the instances.
        address[] memory addedInstances = new address[](instanceCount - 1);
        uint128[] memory addedData = new uint128[](instanceCount - 1);
        address[] memory addedFactories = new address[](instanceCount - 1);
        for (uint256 i = 0; i < instanceCount - 1; i++) {
            addedInstances[i] = instances[i];
            addedData[i] = 1;
            addedFactories[i] = factories[i];
        }
        ensureAddInstanceInfo(addedInstances, addedData, addedFactories);

        // Mix and match updating the registry. The first entry is removed, the
        // second and third are updated, and the last is added.
        uint128[] memory data = new uint128[](instanceCount);
        data[0] = 0;
        data[1] = 2;
        data[2] = 2;
        data[3] = 1;
        factories[0] = address(0);
        registry.setInstanceInfo(instances, data, factories);

        // Ensure that the entries were updated properly in the registry.
        assertEq(registry.getNumberOfInstances(), instanceCount - 1);
        assertEq(registry.getInstanceAtIndex(0), instances[2]);
        assertEq(registry.getInstanceAtIndex(1), instances[1]);
        assertEq(registry.getInstanceAtIndex(2), instances[3]);
        IHyperdriveRegistry.InstanceInfo[] memory info = registry
            .getInstanceInfos(instances);
        for (uint256 i = 0; i < instances.length; i++) {
            assertEq(info[i].data, data[i]);
            assertEq(info[i].factory, factories[i]);
        }

        // Verify that the correct events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            InstanceInfoUpdated.selector
        );
        assertEq(logs.length, instances.length);
        for (uint256 i = 0; i < instances.length; i++) {
            VmSafe.Log memory log = logs[i];
            assertEq(address(uint160(uint256(log.topics[1]))), instances[i]);
            assertEq(uint128(uint256(log.topics[2])), data[i]);
            assertEq(address(uint160(uint256(log.topics[3]))), factories[i]);
        }
    }

    function ensureAddFactoryInfo(
        address[] memory _factories,
        uint128[] memory _data
    ) internal {
        // Ensure that the factories haven't been registered.
        uint256 factoryCountBefore = registry.getNumberOfFactories();
        IHyperdriveRegistry.FactoryInfo[] memory info = registry
            .getFactoryInfos(_factories);
        for (uint256 i = 0; i < _factories.length; i++) {
            assertEq(info[i].data, 0);
        }

        // Register the factories.
        vm.stopPrank();
        vm.startPrank(registry.admin());
        registry.setFactoryInfo(_factories, _data);

        // Ensure that the factories are registered in the list and the mapping.
        assertEq(
            registry.getNumberOfFactories(),
            factoryCountBefore + _factories.length
        );
        address[] memory factories = registry.getFactoriesInRange(
            factoryCountBefore,
            factoryCountBefore + _factories.length
        );
        assertTrue(factories.eq(_factories));
        info = registry.getFactoryInfos(_factories);
        IHyperdriveRegistry.FactoryInfoWithMetadata[]
            memory infoWithMetadata = registry.getFactoryInfosWithMetadata(
                _factories
            );
        for (uint256 i = 0; i < _factories.length; i++) {
            assertEq(
                registry.getFactoryAtIndex(factoryCountBefore + i),
                _factories[i]
            );
            assertEq(registry.getFactoryInfo(_factories[i]).data, _data[i]);
            assertEq(info[i].data, _data[i]);
            assertEq(infoWithMetadata[i].data, _data[i]);
            assertEq(
                infoWithMetadata[i].name,
                IHyperdriveFactory(_factories[i]).name()
            );
            assertEq(
                infoWithMetadata[i].version,
                IHyperdriveFactory(_factories[i]).version()
            );
        }

        // Verify that the correct events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            FactoryInfoUpdated.selector
        );
        assertEq(logs.length, _factories.length);
        for (uint256 i = 0; i < _factories.length; i++) {
            VmSafe.Log memory log = logs[i];
            assertEq(address(uint160(uint256(log.topics[1]))), _factories[i]);
            assertEq(uint128(uint256(log.topics[2])), _data[i]);
        }

        // Start recording logs again.
        vm.recordLogs();
    }

    function ensureUpdateFactoryInfo(
        address[] memory _factories,
        uint128[] memory _data
    ) internal {
        // Get the factory count before the update. This shouldn't change.
        uint256 factoryCountBefore = registry.getNumberOfFactories();

        // Update the factories.
        vm.stopPrank();
        vm.startPrank(registry.admin());
        registry.setFactoryInfo(_factories, _data);

        // Ensure that the factories are still registered in the list and that
        // the associated data has been updated correctly in the mapping.
        assertEq(registry.getNumberOfFactories(), factoryCountBefore);
        IHyperdriveRegistry.FactoryInfo[] memory info = registry
            .getFactoryInfos(_factories);
        IHyperdriveRegistry.FactoryInfoWithMetadata[]
            memory infoWithMetadata = registry.getFactoryInfosWithMetadata(
                _factories
            );
        for (uint256 i = 0; i < _factories.length; i++) {
            assertEq(registry.getFactoryAtIndex(i), _factories[i]);
            assertEq(registry.getFactoryInfo(_factories[i]).data, _data[i]);
            assertEq(info[i].data, _data[i]);
            assertEq(infoWithMetadata[i].data, _data[i]);
            assertEq(
                infoWithMetadata[i].name,
                IHyperdriveFactory(_factories[i]).name()
            );
            assertEq(
                infoWithMetadata[i].version,
                IHyperdriveFactory(_factories[i]).version()
            );
        }

        // Verify that the correct events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            FactoryInfoUpdated.selector
        );
        assertEq(logs.length, _factories.length);
        for (uint256 i = 0; i < _factories.length; i++) {
            VmSafe.Log memory log = logs[i];
            assertEq(address(uint160(uint256(log.topics[1]))), _factories[i]);
            assertEq(uint128(uint256(log.topics[2])), _data[i]);
        }

        // Start recording logs again.
        vm.recordLogs();
    }

    function ensureRemoveFactoryInfo(address[] memory _factories) internal {
        // Get the factory count before the update. This should decrease by
        // the number of factories that we are removing.
        uint256 factoryCountBefore = registry.getNumberOfFactories();

        // Remove the instances.
        uint128[] memory data = new uint128[](_factories.length);
        for (uint256 i = 0; i < _factories.length; i++) {
            data[i] = 0;
        }
        vm.stopPrank();
        vm.startPrank(registry.admin());
        registry.setFactoryInfo(_factories, data);

        // Ensure that the factories have been removed from the list and that
        // the associated data has been removed from the mapping.
        assertEq(
            registry.getNumberOfFactories(),
            factoryCountBefore - _factories.length
        );
        IHyperdriveRegistry.FactoryInfo[] memory info = registry
            .getFactoryInfos(_factories);
        IHyperdriveRegistry.FactoryInfoWithMetadata[]
            memory infoWithMetadata = registry.getFactoryInfosWithMetadata(
                _factories
            );
        for (uint256 i = 0; i < _factories.length; i++) {
            assertEq(registry.getFactoryInfo(_factories[i]).data, data[i]);
            assertEq(info[i].data, 0);
            assertEq(infoWithMetadata[i].data, data[i]);
        }

        // Verify that the correct events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            FactoryInfoUpdated.selector
        );
        assertEq(logs.length, _factories.length);
        for (uint256 i = 0; i < _factories.length; i++) {
            VmSafe.Log memory log = logs[i];
            assertEq(address(uint160(uint256(log.topics[1]))), _factories[i]);
            assertEq(uint128(uint256(log.topics[2])), 0);
        }

        // Start recording logs again.
        vm.recordLogs();
    }

    function ensureAddInstanceInfo(
        address[] memory _instances,
        uint128[] memory _data,
        address[] memory _factories
    ) internal {
        // Ensure that the instances haven't been registered.
        uint256 instanceCountBefore = registry.getNumberOfInstances();
        IHyperdriveRegistry.InstanceInfo[] memory info = registry
            .getInstanceInfos(_instances);
        for (uint256 i = 0; i < _instances.length; i++) {
            assertEq(info[i].data, 0);
            assertEq(info[i].factory, address(0));
        }

        // Register the instances.
        vm.stopPrank();
        vm.startPrank(registry.admin());
        registry.setInstanceInfo(_instances, _data, _factories);

        // Ensure that the instances are registered in the list and the mapping.
        assertEq(
            registry.getNumberOfInstances(),
            instanceCountBefore + _instances.length
        );
        address[] memory instances = registry.getInstancesInRange(
            instanceCountBefore,
            instanceCountBefore + _instances.length
        );
        assertTrue(instances.eq(_instances));
        info = registry.getInstanceInfos(_instances);
        IHyperdriveRegistry.InstanceInfoWithMetadata[]
            memory infoWithMetadata = registry.getInstanceInfosWithMetadata(
                _instances
            );
        for (uint256 i = 0; i < _instances.length; i++) {
            assertEq(
                registry.getInstanceAtIndex(instanceCountBefore + i),
                _instances[i]
            );
            assertEq(registry.getInstanceInfo(_instances[i]).data, _data[i]);
            assertEq(
                registry.getInstanceInfo(_instances[i]).factory,
                _factories[i]
            );
            assertEq(info[i].data, _data[i]);
            assertEq(info[i].factory, _factories[i]);
            assertEq(infoWithMetadata[i].data, _data[i]);
            assertEq(infoWithMetadata[i].factory, _factories[i]);
            assertEq(
                infoWithMetadata[i].name,
                IHyperdrive(_instances[i]).name()
            );
            assertEq(
                infoWithMetadata[i].version,
                IHyperdrive(_instances[i]).version()
            );
        }

        // Verify that the correct events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            InstanceInfoUpdated.selector
        );
        assertEq(logs.length, _instances.length);
        for (uint256 i = 0; i < _instances.length; i++) {
            VmSafe.Log memory log = logs[i];
            assertEq(address(uint160(uint256(log.topics[1]))), _instances[i]);
            assertEq(uint128(uint256(log.topics[2])), _data[i]);
            assertEq(address(uint160(uint256(log.topics[3]))), _factories[i]);
        }

        // Start recording logs again.
        vm.recordLogs();
    }

    function ensureUpdateInstanceInfo(
        address[] memory _instances,
        uint128[] memory _data,
        address[] memory _factories
    ) internal {
        // Get the instance count before the update. This shouldn't change.
        uint256 instanceCountBefore = registry.getNumberOfInstances();

        // Update the instances.
        vm.stopPrank();
        vm.startPrank(registry.admin());
        registry.setInstanceInfo(_instances, _data, _factories);

        // Ensure that the instances are still registered in the list and that
        // the associated data and factories has been updated correctly in the
        // mapping.
        assertEq(registry.getNumberOfInstances(), instanceCountBefore);
        IHyperdriveRegistry.InstanceInfo[] memory info = registry
            .getInstanceInfos(_instances);
        IHyperdriveRegistry.InstanceInfoWithMetadata[]
            memory infoWithMetadata = registry.getInstanceInfosWithMetadata(
                _instances
            );
        for (uint256 i = 0; i < _instances.length; i++) {
            assertEq(registry.getInstanceAtIndex(i), _instances[i]);
            assertEq(registry.getInstanceInfo(_instances[i]).data, _data[i]);
            assertEq(
                registry.getInstanceInfo(_instances[i]).factory,
                _factories[i]
            );
            assertEq(info[i].data, _data[i]);
            assertEq(info[i].factory, _factories[i]);
            assertEq(infoWithMetadata[i].data, _data[i]);
            assertEq(infoWithMetadata[i].factory, _factories[i]);
            assertEq(
                infoWithMetadata[i].name,
                IHyperdrive(_instances[i]).name()
            );
            assertEq(
                infoWithMetadata[i].version,
                IHyperdrive(_instances[i]).version()
            );
        }

        // Verify that the correct events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            InstanceInfoUpdated.selector
        );
        assertEq(logs.length, _instances.length);
        for (uint256 i = 0; i < _instances.length; i++) {
            VmSafe.Log memory log = logs[i];
            assertEq(address(uint160(uint256(log.topics[1]))), _instances[i]);
            assertEq(uint128(uint256(log.topics[2])), _data[i]);
            assertEq(address(uint160(uint256(log.topics[3]))), _factories[i]);
        }

        // Start recording logs again.
        vm.recordLogs();
    }

    function ensureRemoveInstanceInfo(address[] memory _instances) internal {
        // Get the instance count before the update. This should decrease by
        // the number of instances that we are removing.
        uint256 instanceCountBefore = registry.getNumberOfInstances();

        // Remove the instances.
        uint128[] memory data = new uint128[](_instances.length);
        address[] memory factories = new address[](_instances.length);
        for (uint256 i = 0; i < _instances.length; i++) {
            data[i] = 0;
            factories[i] = address(0);
        }
        vm.stopPrank();
        vm.startPrank(registry.admin());
        registry.setInstanceInfo(_instances, data, factories);

        // Ensure that the instances have been removed from the list and that
        // the associated data and factories has been removed from the mapping.
        assertEq(
            registry.getNumberOfInstances(),
            instanceCountBefore - _instances.length
        );
        IHyperdriveRegistry.InstanceInfo[] memory info = registry
            .getInstanceInfos(_instances);
        IHyperdriveRegistry.InstanceInfoWithMetadata[]
            memory infoWithMetadata = registry.getInstanceInfosWithMetadata(
                _instances
            );
        for (uint256 i = 0; i < _instances.length; i++) {
            assertEq(registry.getInstanceInfo(_instances[i]).data, 0);
            assertEq(
                registry.getInstanceInfo(_instances[i]).factory,
                address(0)
            );
            assertEq(info[i].data, 0);
            assertEq(info[i].factory, address(0));
            assertEq(infoWithMetadata[i].data, 0);
            assertEq(infoWithMetadata[i].factory, address(0));
        }

        // Verify that the correct events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            InstanceInfoUpdated.selector
        );
        assertEq(logs.length, _instances.length);
        for (uint256 i = 0; i < _instances.length; i++) {
            VmSafe.Log memory log = logs[i];
            assertEq(address(uint160(uint256(log.topics[1]))), _instances[i]);
            assertEq(uint128(uint256(log.topics[2])), 0);
            assertEq(address(uint160(uint256(log.topics[3]))), address(0));
        }

        // Start recording logs again.
        vm.recordLogs();
    }
}
