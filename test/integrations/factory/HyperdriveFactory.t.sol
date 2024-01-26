// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626HyperdriveCoreDeployer } from "contracts/src/deployers/erc4626/ERC4626HyperdriveCoreDeployer.sol";
import { ERC4626HyperdriveDeployerCoordinator } from "contracts/src/deployers/erc4626/ERC4626HyperdriveDeployerCoordinator.sol";
import { ERC4626Target0Deployer } from "contracts/src/deployers/erc4626/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "contracts/src/deployers/erc4626/ERC4626Target1Deployer.sol";
import { ERC4626Target2Deployer } from "contracts/src/deployers/erc4626/ERC4626Target2Deployer.sol";
import { ERC4626Target3Deployer } from "contracts/src/deployers/erc4626/ERC4626Target3Deployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { MockERC4626, ERC20 } from "contracts/test/MockERC4626.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveFactory } from "contracts/src/interfaces/IHyperdriveFactory.sol";
import { IDeployerCoordinator } from "contracts/src/interfaces/IDeployerCoordinator.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockHyperdriveDeployer, MockHyperdriveTargetDeployer } from "contracts/test/MockHyperdriveDeployer.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract HyperdriveFactoryTest is HyperdriveTest {
    HyperdriveFactory internal factory;

    event DefaultPausersUpdated(address[] newDefaultPausers);

    event FeeCollectorUpdated(address indexed newFeeCollector);

    event DeployerCoordinatorAdded(address indexed deployerCoordinator);

    event DeployerCoordinatorRemoved(address indexed deployerCoordinator);

    event HyperdriveGovernanceUpdated(address indexed hyperdriveGovernance);

    event LinkerFactoryUpdated(address indexed newLinkerFactory);

    event LinkerCodeHashUpdated(bytes32 indexed newLinkerCodeHash);

    event CheckpointDurationResolutionUpdated(
        uint256 newCheckpointDurationResolution
    );

    event MaxCheckpointDurationUpdated(uint256 newMaxCheckpointDuration);

    event MinCheckpointDurationUpdated(uint256 newMinCheckpointDuration);

    event MaxPositionDurationUpdated(uint256 newMaxPositionDuration);

    event MinPositionDurationUpdated(uint256 newMinPositionDuration);

    event MaxFixedAPRUpdated(uint256 newMaxFixedAPR);

    event MinFixedAPRUpdated(uint256 newMinFixedAPR);

    event MaxTimestretchAPRUpdated(uint256 newMaxTimestretchAPR);

    event MinTimestretchAPRUpdated(uint256 newMinTimestretchAPR);

    event MaxFeesUpdated(IHyperdrive.Fees newMaxFees);

    event MinFeesUpdated(IHyperdrive.Fees newMinFees);

    function setUp() public override {
        super.setUp();

        // Deploy the factory.
        vm.stopPrank();
        vm.startPrank(alice);
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        HyperdriveFactory.FactoryConfig memory config = HyperdriveFactory
            .FactoryConfig({
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
                minTimestretchAPR: 0.005e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees({
                    curve: 0.001e18,
                    flat: 0.0001e18,
                    governanceLP: 0.15e18,
                    governanceZombie: 0.03e18
                }),
                maxFees: IHyperdrive.Fees({
                    curve: 0.1e18,
                    flat: 0.01e18,
                    governanceLP: 0.15e18,
                    governanceZombie: 0.03e18
                }),
                linkerFactory: address(0xdeadbeef),
                linkerCodeHash: bytes32(uint256(0xdeadbabe))
            });
        factory = new HyperdriveFactory(config);
    }

    function test_constructor() external {
        address[] memory defaults = new address[](1);
        defaults[0] = bob;

        // Ensure that the factory can't be constructed with a minimum
        // checkpoint duration less than the checkpoint duration resolution.
        vm.expectRevert(
            IHyperdriveFactory.InvalidMinCheckpointDuration.selector
        );
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 30 minutes,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum
        // checkpoint duration that isn't a multiple of the checkpoint duration
        // resolution.
        vm.expectRevert(
            IHyperdriveFactory.InvalidMinCheckpointDuration.selector
        );
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 1.5 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // checkpoint duration that is less than the minimum checkpoint
        // duration.
        vm.expectRevert(
            IHyperdriveFactory.InvalidMaxCheckpointDuration.selector
        );
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 7 hours,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // checkpoint duration that isn't a multiple of the checkpoint duration
        // resolution.
        vm.expectRevert(
            IHyperdriveFactory.InvalidMaxCheckpointDuration.selector
        );
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 8.5 hours,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum position
        // duration that is less than the maximum checkpoint duration.
        vm.expectRevert(IHyperdriveFactory.InvalidMinPositionDuration.selector);
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 8 hours,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum
        // position duration that isn't a multiple of the checkpoint duration
        // resolution.
        vm.expectRevert(IHyperdriveFactory.InvalidMinPositionDuration.selector);
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days + 30 minutes,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // position duration that is less than the minimum position duration.
        vm.expectRevert(IHyperdriveFactory.InvalidMaxPositionDuration.selector);
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 6 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // position duration that isn't a multiple of the checkpoint duration
        // resolution.
        vm.expectRevert(IHyperdriveFactory.InvalidMaxPositionDuration.selector);
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days + 30 minutes,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // curve fee greater than 1.
        vm.expectRevert(IHyperdriveFactory.InvalidMaxFees.selector);
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(2 * ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // flat fee greater than 1.
        vm.expectRevert(IHyperdriveFactory.InvalidMaxFees.selector);
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, 2 * ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // governance LP fee greater than 1.
        vm.expectRevert(IHyperdriveFactory.InvalidMaxFees.selector);
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, 2 * ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // governance zombie fee greater than 1.
        vm.expectRevert(IHyperdriveFactory.InvalidMaxFees.selector);
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, 2 * ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum
        // curve fee greater than the maximum curve fee.
        vm.expectRevert(IHyperdriveFactory.InvalidMinFees.selector);
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(ONE, 0, 0, 0),
                maxFees: IHyperdrive.Fees(0, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum
        // flat fee greater than the maximum flat fee.
        vm.expectRevert(IHyperdriveFactory.InvalidMinFees.selector);
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, ONE, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, 0, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum
        // governance LP fee greater than the maximum governance LP fee.
        vm.expectRevert(IHyperdriveFactory.InvalidMinFees.selector);
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, ONE, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, 0, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum
        // governance zombie fee greater than the maximum governance zombie fee.
        vm.expectRevert(IHyperdriveFactory.InvalidMinFees.selector);
        new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, ONE),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, 0),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can be constructed with a valid configuration
        // and that the factory's parameters are set correctly.
        HyperdriveFactory.FactoryConfig memory config = HyperdriveFactory
            .FactoryConfig({
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
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0xdeadbeef),
                linkerCodeHash: bytes32(uint256(0xdeadbabe))
            });
        factory = new HyperdriveFactory(config);
        assertEq(factory.governance(), config.governance);
        assertEq(factory.hyperdriveGovernance(), config.hyperdriveGovernance);
        assertEq(factory.linkerFactory(), config.linkerFactory);
        assertEq(factory.linkerCodeHash(), config.linkerCodeHash);
        assertEq(factory.feeCollector(), config.feeCollector);
        assertEq(
            factory.checkpointDurationResolution(),
            config.checkpointDurationResolution
        );
        assertEq(factory.minCheckpointDuration(), config.minCheckpointDuration);
        assertEq(factory.maxCheckpointDuration(), config.maxCheckpointDuration);
        assertEq(factory.minPositionDuration(), config.minPositionDuration);
        assertEq(factory.maxPositionDuration(), config.maxPositionDuration);
        assertEq(factory.minTimestretchAPR(), config.minTimestretchAPR);
        assertEq(factory.maxTimestretchAPR(), config.maxTimestretchAPR);
        assertEq(
            keccak256(abi.encode(factory.minFees())),
            keccak256(abi.encode(config.minFees))
        );
        assertEq(
            keccak256(abi.encode(factory.maxFees())),
            keccak256(abi.encode(config.maxFees))
        );
        assertEq(
            keccak256(abi.encode(factory.defaultPausers())),
            keccak256(abi.encode(config.defaultPausers))
        );
    }

    function test_updateGovernance() external {
        address newGovernance = address(0xdeadbeef);

        // Ensure that governance can't be updated by someone other than
        // the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateGovernance(newGovernance);

        // Ensure that governance was updated successfully and that the correct
        // event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit GovernanceUpdated(newGovernance);
        factory.updateGovernance(newGovernance);
        assertEq(factory.governance(), newGovernance);
    }

    function test_updateHyperdriveGovernance() external {
        address newHyperdriveGovernance = address(0xdeadbeef);

        // Ensure that hyperdrive governance can't be updated by someone other
        // than the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateHyperdriveGovernance(newHyperdriveGovernance);

        // Ensure that hyperdrive governance was updated successfully and that
        // the correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit HyperdriveGovernanceUpdated(newHyperdriveGovernance);
        factory.updateHyperdriveGovernance(newHyperdriveGovernance);
        assertEq(factory.hyperdriveGovernance(), newHyperdriveGovernance);
    }

    function test_updateLinkerFactory() external {
        address newLinkerFactory = address(0xdeadbeef);

        // Ensure that the linker factory can't be updated by someone other
        // than the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateLinkerFactory(newLinkerFactory);

        // Ensure that the linker factory was updated successfully and that the
        // correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit LinkerFactoryUpdated(newLinkerFactory);
        factory.updateLinkerFactory(newLinkerFactory);
        assertEq(factory.linkerFactory(), newLinkerFactory);
    }

    function test_updateLinkerCodeHash() external {
        bytes32 newLinkerCodeHash = bytes32(uint256(0xdeadbeef));

        // Ensure that the linker code hash can't be updated by someone other
        // than the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateLinkerCodeHash(newLinkerCodeHash);

        // Ensure that the linker code hash was updated successfully and that
        // the correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit LinkerCodeHashUpdated(newLinkerCodeHash);
        factory.updateLinkerCodeHash(newLinkerCodeHash);
        assertEq(factory.linkerCodeHash(), newLinkerCodeHash);
    }

    function test_updateFeeCollector() external {
        address newFeeCollector = address(0xdeadbeef);

        // Ensure that the fee collector can't be updated by someone other than
        // the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateFeeCollector(newFeeCollector);

        // Ensure that the fee collector was updated successfully and that the
        // correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit FeeCollectorUpdated(newFeeCollector);
        factory.updateFeeCollector(newFeeCollector);
        assertEq(factory.feeCollector(), newFeeCollector);
    }

    function test_updateCheckpointDurationResolution() external {
        uint256 newCheckpointDurationResolution = 30 minutes;

        // Ensure that the checkpoint duration resolution can't be updated by
        // someone other than the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateCheckpointDurationResolution(
            newCheckpointDurationResolution
        );

        // Ensure that the checkpoint duration resolution can't be set to a
        // value that doesn't divide the min checkpoint duration.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMinCheckpointDuration(3 hours);
        factory.updateMaxCheckpointDuration(4 hours);
        factory.updateMinPositionDuration(4 hours);
        factory.updateMaxPositionDuration(4 hours);
        vm.expectRevert(
            IHyperdriveFactory.InvalidCheckpointDurationResolution.selector
        );
        factory.updateCheckpointDurationResolution(2 hours);

        // Ensure that the checkpoint duration resolution can't be set to a
        // value that doesn't divide the max checkpoint duration.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMinCheckpointDuration(3 hours);
        factory.updateMaxCheckpointDuration(4 hours);
        factory.updateMinPositionDuration(4 hours);
        factory.updateMaxPositionDuration(4 hours);
        vm.expectRevert(
            IHyperdriveFactory.InvalidCheckpointDurationResolution.selector
        );
        factory.updateCheckpointDurationResolution(3 hours);

        // Ensure that the checkpoint duration resolution can't be set to a
        // value that doesn't divide the min position duration.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMinCheckpointDuration(3 hours);
        factory.updateMaxCheckpointDuration(3 hours);
        factory.updateMinPositionDuration(4 hours);
        factory.updateMaxPositionDuration(6 hours);
        vm.expectRevert(
            IHyperdriveFactory.InvalidCheckpointDurationResolution.selector
        );
        factory.updateCheckpointDurationResolution(3 hours);

        // Ensure that the checkpoint duration resolution can't be set to a
        // value that doesn't divide the max position duration.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMinCheckpointDuration(3 hours);
        factory.updateMaxCheckpointDuration(3 hours);
        factory.updateMinPositionDuration(3 hours);
        factory.updateMaxPositionDuration(4 hours);
        vm.expectRevert(
            IHyperdriveFactory.InvalidCheckpointDurationResolution.selector
        );
        factory.updateCheckpointDurationResolution(3 hours);

        // Ensure that the fee collector was updated successfully and that the
        // correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMaxPositionDuration(10 * 365 days);
        factory.updateMinPositionDuration(7 days);
        factory.updateMaxCheckpointDuration(1 days);
        factory.updateMinCheckpointDuration(8 hours);
        vm.expectEmit(true, true, true, true);
        emit CheckpointDurationResolutionUpdated(
            newCheckpointDurationResolution
        );
        factory.updateCheckpointDurationResolution(
            newCheckpointDurationResolution
        );
        assertEq(
            factory.checkpointDurationResolution(),
            newCheckpointDurationResolution
        );
    }

    function test_updateMaxCheckpointDuration() external {
        uint256 newMaxCheckpointDuration = 2 days;

        // Ensure that the max checkpoint duration can't be updated by someone
        // other than the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateMaxCheckpointDuration(newMaxCheckpointDuration);

        // Ensure that the max checkpoint duration can't be set to a value
        // less than the min checkpoint duration.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 minCheckpointDuration = factory.minCheckpointDuration();
        vm.expectRevert(
            IHyperdriveFactory.InvalidMaxCheckpointDuration.selector
        );
        factory.updateMaxCheckpointDuration(minCheckpointDuration - 1);

        // Ensure that the max checkpoint duration can't be set to a value
        // that isn't a multiple of the checkpoint duration resolution.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 checkpointDurationResolution = factory
            .checkpointDurationResolution();
        vm.expectRevert(
            IHyperdriveFactory.InvalidMaxCheckpointDuration.selector
        );
        factory.updateMaxCheckpointDuration(
            minCheckpointDuration + checkpointDurationResolution / 2
        );

        // Ensure that the max checkpoint duration can't be set to a value
        // greater than the min position duration.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 minPositionDuration = factory.minPositionDuration();
        vm.expectRevert(
            IHyperdriveFactory.InvalidMaxCheckpointDuration.selector
        );
        factory.updateMaxCheckpointDuration(minPositionDuration + 1);

        // Ensure that the max checkpoint duration was updated successfully and
        // that the correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit MaxCheckpointDurationUpdated(newMaxCheckpointDuration);
        factory.updateMaxCheckpointDuration(newMaxCheckpointDuration);
        assertEq(factory.maxCheckpointDuration(), newMaxCheckpointDuration);
    }

    function test_updateMinCheckpointDuration() external {
        uint256 newMinCheckpointDuration = 12 hours;

        // Ensure that the min checkpoint duration can't be updated by someone
        // other than the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateMinCheckpointDuration(newMinCheckpointDuration);

        // Ensure that the min checkpoint duration can't be set to a value
        // less than the checkpoint duration resolution.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 checkpointDurationResolution = factory
            .checkpointDurationResolution();
        vm.expectRevert(
            IHyperdriveFactory.InvalidMinCheckpointDuration.selector
        );
        factory.updateMinCheckpointDuration(checkpointDurationResolution - 1);

        // Ensure that the min checkpoint duration can't be set to a value
        // that isn't a multiple of the checkpoint duration resolution.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 minCheckpointDuration = factory.minCheckpointDuration();
        vm.expectRevert(
            IHyperdriveFactory.InvalidMinCheckpointDuration.selector
        );
        factory.updateMinCheckpointDuration(
            minCheckpointDuration + checkpointDurationResolution / 2
        );

        // Ensure that the min checkpoint duration can't be set to a value
        // greater than the max checkpoint duration.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 maxCheckpointDuration = factory.maxCheckpointDuration();
        vm.expectRevert(
            IHyperdriveFactory.InvalidMinCheckpointDuration.selector
        );
        factory.updateMinCheckpointDuration(maxCheckpointDuration + 1);

        // Ensure that the min checkpoint duration was updated successfully and
        // that the correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit MinCheckpointDurationUpdated(newMinCheckpointDuration);
        factory.updateMinCheckpointDuration(newMinCheckpointDuration);
        assertEq(factory.minCheckpointDuration(), newMinCheckpointDuration);
    }

    function test_updateMaxPositionDuration() external {
        uint256 newMaxPositionDuration = 30 * 365 days;

        // Ensure that the max position duration can't be updated by someone
        // other than the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateMaxPositionDuration(newMaxPositionDuration);

        // Ensure that the max position duration can't be set to a value
        // less than the min position duration.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 minPositionDuration = factory.minPositionDuration();
        vm.expectRevert(IHyperdriveFactory.InvalidMaxPositionDuration.selector);
        factory.updateMaxPositionDuration(minPositionDuration - 1);

        // Ensure that the max position duration can't be set to a value
        // that isn't a multiple of the checkpoint duration resolution.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 checkpointDurationResolution = factory
            .checkpointDurationResolution();
        vm.expectRevert(IHyperdriveFactory.InvalidMaxPositionDuration.selector);
        factory.updateMaxPositionDuration(
            minPositionDuration + checkpointDurationResolution / 2
        );

        // Ensure that the max position duration was updated successfully and
        // that the correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit MaxPositionDurationUpdated(newMaxPositionDuration);
        factory.updateMaxPositionDuration(newMaxPositionDuration);
        assertEq(factory.maxPositionDuration(), newMaxPositionDuration);
    }

    function test_updateMinPositionDuration() external {
        uint256 newMinPositionDuration = 3 days;

        // Ensure that the min position duration can't be updated by someone
        // other than the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateMinPositionDuration(newMinPositionDuration);

        // Ensure that the min position duration can't be set to a value
        // less than the max checkpoint duration.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 checkpointDurationResolution = factory
            .checkpointDurationResolution();
        vm.expectRevert(IHyperdriveFactory.InvalidMinPositionDuration.selector);
        factory.updateMinPositionDuration(checkpointDurationResolution - 1);

        // Ensure that the min position duration can't be set to a value that
        // isn't a multiple of the checkpoint duration resolution.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 maxCheckpointDuration = factory.maxCheckpointDuration();
        vm.expectRevert(IHyperdriveFactory.InvalidMinPositionDuration.selector);
        factory.updateMinPositionDuration(
            maxCheckpointDuration + checkpointDurationResolution / 2
        );

        // Ensure that the min position duration can't be set to a value greater
        // than the max position duration.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 maxPositionDuration = factory.maxPositionDuration();
        vm.expectRevert(IHyperdriveFactory.InvalidMinPositionDuration.selector);
        factory.updateMinPositionDuration(maxPositionDuration + 1);

        // Ensure that the min position duration was updated successfully and
        // that the correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit MinPositionDurationUpdated(newMinPositionDuration);
        factory.updateMinPositionDuration(newMinPositionDuration);
        assertEq(factory.minPositionDuration(), newMinPositionDuration);
    }

    function test_updateMaxFixedAPR() external {
        uint256 newMaxFixedAPR = 0.25e18;

        // Ensure that the max fixed APR can't be updated by someone other than
        // the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateMaxFixedAPR(newMaxFixedAPR);

        // Ensure that the max fixed APR can't be set to a value less than the
        // min fixed APR.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 minFixedAPR = factory.minFixedAPR();
        vm.expectRevert(IHyperdriveFactory.InvalidMaxFixedAPR.selector);
        factory.updateMaxFixedAPR(minFixedAPR - 1);

        // Ensure that the max fixed APR was updated successfully and that the
        // correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit MaxFixedAPRUpdated(newMaxFixedAPR);
        factory.updateMaxFixedAPR(newMaxFixedAPR);
        assertEq(factory.maxFixedAPR(), newMaxFixedAPR);
    }

    function test_updateMinFixedAPR() external {
        uint256 newMinFixedAPR = 0.01e18;

        // Ensure that the min fixed APR can't be updated by someone other than
        // the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateMinFixedAPR(newMinFixedAPR);

        // Ensure that the min fixed APR can't be set to a value greater than
        // the max fixed APR.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 maxFixedAPR = factory.maxFixedAPR();
        vm.expectRevert(IHyperdriveFactory.InvalidMinFixedAPR.selector);
        factory.updateMinFixedAPR(maxFixedAPR + 1);

        // Ensure that the min fixed APR was updated successfully and that the
        // correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit MinFixedAPRUpdated(newMinFixedAPR);
        factory.updateMinFixedAPR(newMinFixedAPR);
        assertEq(factory.minFixedAPR(), newMinFixedAPR);
    }

    function test_updateMaxTimestretchAPR() external {
        uint256 newMaxTimestretchAPR = 0.25e18;

        // Ensure that the max timestretch APR can't be updated by someone
        // other than the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateMaxTimestretchAPR(newMaxTimestretchAPR);

        // Ensure that the max timestretch APR can't be set to a value
        // less than the min timestretch APR.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 minTimestretchAPR = factory.minTimestretchAPR();
        vm.expectRevert(IHyperdriveFactory.InvalidMaxTimestretchAPR.selector);
        factory.updateMaxTimestretchAPR(minTimestretchAPR - 1);

        // Ensure that the max timestretch APR was updated successfully and
        // that the correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit MaxTimestretchAPRUpdated(newMaxTimestretchAPR);
        factory.updateMaxTimestretchAPR(newMaxTimestretchAPR);
        assertEq(factory.maxTimestretchAPR(), newMaxTimestretchAPR);
    }

    function test_updateMinTimestretchAPR() external {
        uint256 newMinTimestretchAPR = 0.01e18;

        // Ensure that the min timestretch APR can't be updated by someone
        // other than the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateMinTimestretchAPR(newMinTimestretchAPR);

        // Ensure that the min timestretch APR can't be set to a value
        // greater than the max timestretch APR.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        uint256 maxTimestretchAPR = factory.maxTimestretchAPR();
        vm.expectRevert(IHyperdriveFactory.InvalidMinTimestretchAPR.selector);
        factory.updateMinTimestretchAPR(maxTimestretchAPR + 1);

        // Ensure that the min timestretch APR was updated successfully and
        // that the correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit MinTimestretchAPRUpdated(newMinTimestretchAPR);
        factory.updateMinTimestretchAPR(newMinTimestretchAPR);
        assertEq(factory.minTimestretchAPR(), newMinTimestretchAPR);
    }

    function test_updateMaxFees() external {
        IHyperdrive.Fees memory newMaxFees = IHyperdrive.Fees({
            curve: 0.1e18,
            flat: 0.001e18,
            governanceLP: 0.3e18,
            governanceZombie: 0.1e18
        });

        // Ensure that the maximum fees can't be updated by someone other than
        // the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateMaxFees(newMaxFees);

        // Ensure that the maximum fees can't be set when the curve fee is
        // greater than 1.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectRevert(IHyperdriveFactory.InvalidMaxFees.selector);
        factory.updateMaxFees(
            IHyperdrive.Fees({
                curve: 1.1e18,
                flat: 0.001e18,
                governanceLP: 0.3e18,
                governanceZombie: 0.1e18
            })
        );

        // Ensure that the maximum fees can't be set when the flat fee is
        // greater than 1.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectRevert(IHyperdriveFactory.InvalidMaxFees.selector);
        factory.updateMaxFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 1.001e18,
                governanceLP: 0.3e18,
                governanceZombie: 0.1e18
            })
        );

        // Ensure that the maximum fees can't be set when the governance LP fee
        // is greater than 1.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectRevert(IHyperdriveFactory.InvalidMaxFees.selector);
        factory.updateMaxFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 1.3e18,
                governanceZombie: 0.1e18
            })
        );

        // Ensure that the maximum fees can't be set when the governance zombie
        // fee is greater than 1.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectRevert(IHyperdriveFactory.InvalidMaxFees.selector);
        factory.updateMaxFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.3e18,
                governanceZombie: 1.1e18
            })
        );

        // Ensure that the maximum fees can't be set when the curve fee is
        // less than the minimum curve fee.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMinFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.15e18,
                governanceZombie: 0.03e18
            })
        );
        vm.expectRevert(IHyperdriveFactory.InvalidMaxFees.selector);
        factory.updateMaxFees(
            IHyperdrive.Fees({
                curve: 0.05e18,
                flat: 0.001e18,
                governanceLP: 0.15e18,
                governanceZombie: 0.1e18
            })
        );

        // Ensure that the maximum fees can't be set when the flat fee is
        // less than the minimum flat fee.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMinFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.15e18,
                governanceZombie: 0.03e18
            })
        );
        vm.expectRevert(IHyperdriveFactory.InvalidMaxFees.selector);
        factory.updateMaxFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.0005e18,
                governanceLP: 0.3e18,
                governanceZombie: 0.1e18
            })
        );

        // Ensure that the maximum fees can't be set when the governance LP fee
        // is less than the minimum governance LP fee.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMinFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.15e18,
                governanceZombie: 0.03e18
            })
        );
        vm.expectRevert(IHyperdriveFactory.InvalidMaxFees.selector);
        factory.updateMaxFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.075e18,
                governanceZombie: 0.1e18
            })
        );

        // Ensure that the maximum fees can't be set when the governance zombie
        // fee is less than the minimum governance zombie fee.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMinFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.15e18,
                governanceZombie: 0.03e18
            })
        );
        vm.expectRevert(IHyperdriveFactory.InvalidMaxFees.selector);
        factory.updateMaxFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.3e18,
                governanceZombie: 0.01e18
            })
        );

        // Ensure that the maximum fees were updated successfully and that the
        // correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMinFees(
            IHyperdrive.Fees({
                curve: 0.05e18,
                flat: 0.0005e18,
                governanceLP: 0.15e18,
                governanceZombie: 0.03e18
            })
        );
        vm.expectEmit(true, true, true, true);
        emit MaxFeesUpdated(newMaxFees);
        factory.updateMaxFees(newMaxFees);
        assertEq(
            keccak256(abi.encode(factory.maxFees())),
            keccak256(abi.encode(newMaxFees))
        );
    }

    function test_updateMinFees() external {
        IHyperdrive.Fees memory newMinFees = IHyperdrive.Fees({
            curve: 0.05e18,
            flat: 0.0005e18,
            governanceLP: 0.15e18,
            governanceZombie: 0.05e18
        });

        // Ensure that the minimum fees can't be updated by someone other than
        // the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateMinFees(newMinFees);

        // Ensure that the minimum fees can't be set when the curve fee is
        // greater than the maximum curve fee.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMaxFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.3e18,
                governanceZombie: 0.1e18
            })
        );
        vm.expectRevert(IHyperdriveFactory.InvalidMinFees.selector);
        factory.updateMinFees(
            IHyperdrive.Fees({
                curve: 0.2e18,
                flat: 0.001e18,
                governanceLP: 0.3e18,
                governanceZombie: 0.1e18
            })
        );

        // Ensure that the minimum fees can't be set when the flat fee is
        // greater than the maximum flat fee.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMaxFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.3e18,
                governanceZombie: 0.1e18
            })
        );
        vm.expectRevert(IHyperdriveFactory.InvalidMinFees.selector);
        factory.updateMinFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.002e18,
                governanceLP: 0.3e18,
                governanceZombie: 0.1e18
            })
        );

        // Ensure that the minimum fees can't be set when the governance LP fee
        // is greater than the maximum governance LP fee.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMaxFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.3e18,
                governanceZombie: 0.1e18
            })
        );
        vm.expectRevert(IHyperdriveFactory.InvalidMinFees.selector);
        factory.updateMinFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.4e18,
                governanceZombie: 0.1e18
            })
        );

        // Ensure that the minimum fees can't be set when the governance zombie
        // fee is greater than the maximum governance zombie fee.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMaxFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.3e18,
                governanceZombie: 0.1e18
            })
        );
        vm.expectRevert(IHyperdriveFactory.InvalidMinFees.selector);
        factory.updateMinFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.3e18,
                governanceZombie: 0.2e18
            })
        );

        // Ensure that the maximum fees were updated successfully and that the
        // correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        factory.updateMaxFees(
            IHyperdrive.Fees({
                curve: 0.1e18,
                flat: 0.001e18,
                governanceLP: 0.3e18,
                governanceZombie: 0.1e18
            })
        );
        vm.expectEmit(true, true, true, true);
        emit MinFeesUpdated(newMinFees);
        factory.updateMinFees(newMinFees);
        assertEq(
            keccak256(abi.encode(factory.minFees())),
            keccak256(abi.encode(newMinFees))
        );
    }

    function test_updateDefaultPausers() external {
        address[] memory newDefaultPausers = new address[](2);
        newDefaultPausers[0] = bob;
        newDefaultPausers[1] = celine;

        // Ensure that the default pausers can't be updated by someone other
        // than the current governance.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.updateDefaultPausers(newDefaultPausers);

        // Ensure that the default pausers were updated successfully and that
        // the correct event was emitted.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit DefaultPausersUpdated(newDefaultPausers);
        factory.updateDefaultPausers(newDefaultPausers);
        assertEq(
            keccak256(abi.encode(factory.defaultPausers())),
            keccak256(abi.encode(newDefaultPausers))
        );
    }

    function test_deployAndInitialize() external {
        // Deploy an ERC4626 vault.
        ERC20Mintable base = new ERC20Mintable(
            "Base",
            "BASE",
            18,
            address(0),
            false
        );
        IERC4626 vault = IERC4626(
            address(
                new MockERC4626(base, "Vault", "VAULT", 0, address(0), false)
            )
        );
        base.mint(bob, 10_000e18);
        base.approve(address(factory), 10_000e18);

        // Add a deployer coordinator to the factory.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        address deployerCoordinator = address(
            new ERC4626HyperdriveDeployerCoordinator(
                address(new ERC4626HyperdriveCoreDeployer()),
                address(new ERC4626Target0Deployer()),
                address(new ERC4626Target1Deployer()),
                address(new ERC4626Target2Deployer()),
                address(new ERC4626Target3Deployer())
            )
        );
        factory.addDeployerCoordinator(deployerCoordinator);

        // Define a config that can be reused for each test.
        IHyperdrive.PoolDeployConfig memory config = IHyperdrive
            .PoolDeployConfig({
                baseToken: IERC20(address(base)),
                minimumShareReserves: 1e18,
                minimumTransactionAmount: 1e15,
                positionDuration: 365 days,
                checkpointDuration: 1 days,
                timeStretch: HyperdriveUtils.calculateTimeStretch(
                    0.05e18,
                    365 days
                ),
                governance: address(0),
                feeCollector: address(0),
                fees: IHyperdrive.Fees(0.01e18, 0.001e18, 0.15e18, 0.03e18),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            });

        // Ensure that an instance can't be deployed with a coordinator that
        // hasn't been added.
        vm.stopPrank();
        vm.startPrank(bob);
        bytes memory extraData = abi.encode(vault);
        vm.expectRevert(IHyperdriveFactory.InvalidDeployerCoordinator.selector);
        factory.deployAndInitialize(
            address(0xdeadbeef),
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );

        // Ensure than an instance can't be deployed with a checkpoint duration
        // that is greater than the maximum checkpoint duration.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 oldCheckpointDuration = config.checkpointDuration;
        config.checkpointDuration =
            factory.maxCheckpointDuration() +
            factory.checkpointDurationResolution();
        vm.expectRevert(IHyperdriveFactory.InvalidCheckpointDuration.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.checkpointDuration = oldCheckpointDuration;

        // Ensure than an instance can't be deployed with a checkpoint duration
        // that is less than the minimum checkpoint duration.
        vm.stopPrank();
        vm.startPrank(bob);
        oldCheckpointDuration = config.checkpointDuration;
        config.checkpointDuration =
            factory.minCheckpointDuration() -
            factory.checkpointDurationResolution();
        vm.expectRevert(IHyperdriveFactory.InvalidCheckpointDuration.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.checkpointDuration = oldCheckpointDuration;

        // Ensure than an instance can't be deployed with a checkpoint duration
        // that isn't a multiple of the checkpoint duration resolution.
        vm.stopPrank();
        vm.startPrank(bob);
        oldCheckpointDuration = config.checkpointDuration;
        config.checkpointDuration = factory.minCheckpointDuration() + 1;
        vm.expectRevert(IHyperdriveFactory.InvalidCheckpointDuration.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.checkpointDuration = oldCheckpointDuration;

        // Ensure than an instance can't be deployed with a position duration
        // that is greater than the maximum position duration.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 oldPositionDuration = config.positionDuration;
        config.positionDuration =
            factory.maxPositionDuration() +
            factory.checkpointDurationResolution();
        vm.expectRevert(IHyperdriveFactory.InvalidPositionDuration.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.positionDuration = oldPositionDuration;

        // Ensure than an instance can't be deployed with a position duration
        // that is less than the minimum position duration.
        vm.stopPrank();
        vm.startPrank(bob);
        oldPositionDuration = config.positionDuration;
        config.positionDuration =
            factory.minPositionDuration() -
            factory.checkpointDurationResolution();
        vm.expectRevert(IHyperdriveFactory.InvalidPositionDuration.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.positionDuration = oldPositionDuration;

        // Ensure than an instance can't be deployed with a position duration
        // that isn't a multiple of the checkpoint duration.
        vm.stopPrank();
        vm.startPrank(bob);
        oldPositionDuration = config.positionDuration;
        config.positionDuration = 365 * config.checkpointDuration + 1;
        vm.expectRevert(IHyperdriveFactory.InvalidPositionDuration.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.positionDuration = oldPositionDuration;

        // FIXME: Add cases for the min and max fixed APR.

        // FIXME: Add cases for the min and max time stretch APR.

        // FIXME: Add cases for the additional checks on the timestretch APR.

        // Ensure than an instance can't be deployed with a curve fee greater
        // than the maximum curve fee.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 oldCurveFee = config.fees.curve;
        config.fees.curve = factory.maxFees().curve + 1;
        vm.expectRevert(IHyperdriveFactory.InvalidFees.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.fees.curve = oldCurveFee;

        // Ensure than an instance can't be deployed with a curve fee less
        // than the minimum curve fee.
        vm.stopPrank();
        vm.startPrank(bob);
        oldCurveFee = config.fees.curve;
        config.fees.curve = factory.minFees().curve - 1;
        vm.expectRevert(IHyperdriveFactory.InvalidFees.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.fees.curve = oldCurveFee;

        // Ensure than an instance can't be deployed with a flat fee greater
        // than the maximum flat fee.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 oldFlatFee = config.fees.flat;
        config.fees.flat = factory.maxFees().flat + 1;
        vm.expectRevert(IHyperdriveFactory.InvalidFees.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.fees.flat = oldFlatFee;

        // Ensure than an instance can't be deployed with a flat fee less
        // than the minimum flat fee.
        vm.stopPrank();
        vm.startPrank(bob);
        oldFlatFee = config.fees.flat;
        config.fees.flat = factory.minFees().flat - 1;
        vm.expectRevert(IHyperdriveFactory.InvalidFees.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.fees.flat = oldFlatFee;

        // Ensure than an instance can't be deployed with a governance LP fee
        // greater than the maximum governance LP fee.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 oldGovernanceLPFee = config.fees.governanceLP;
        config.fees.governanceLP = factory.maxFees().governanceLP + 1;
        vm.expectRevert(IHyperdriveFactory.InvalidFees.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.fees.governanceLP = oldGovernanceLPFee;

        // Ensure than an instance can't be deployed with a governance LP fee
        // less than the minimum governance LP fee.
        vm.stopPrank();
        vm.startPrank(bob);
        oldGovernanceLPFee = config.fees.governanceLP;
        config.fees.governanceLP = factory.minFees().governanceLP - 1;
        vm.expectRevert(IHyperdriveFactory.InvalidFees.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.fees.governanceLP = oldGovernanceLPFee;

        // Ensure than an instance can't be deployed with a governance zombie
        // fee greater than the maximum governance zombie fee.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 oldGovernanceZombieFee = config.fees.governanceZombie;
        config.fees.governanceZombie = factory.maxFees().governanceZombie + 1;
        vm.expectRevert(IHyperdriveFactory.InvalidFees.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.fees.governanceZombie = oldGovernanceZombieFee;

        // Ensure than an instance can't be deployed with a governance zombie
        // fee less than the minimum governance zombie fee.
        vm.stopPrank();
        vm.startPrank(bob);
        oldGovernanceZombieFee = config.fees.governanceZombie;
        config.fees.governanceZombie = factory.minFees().governanceZombie - 1;
        vm.expectRevert(IHyperdriveFactory.InvalidFees.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.fees.governanceZombie = oldGovernanceZombieFee;

        // Ensure than an instance can't be deployed with a linker factory that
        // is set.
        vm.stopPrank();
        vm.startPrank(bob);
        address oldLinkerFactory = config.linkerFactory;
        config.linkerFactory = address(0xdeadbeef);
        vm.expectRevert(IHyperdriveFactory.InvalidDeployConfig.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.linkerFactory = oldLinkerFactory;

        // Ensure than an instance can't be deployed with a linker code hash
        // that is set.
        vm.stopPrank();
        vm.startPrank(bob);
        bytes32 oldLinkerCodeHash = config.linkerCodeHash;
        config.linkerCodeHash = bytes32(uint256(0xdeadbeef));
        vm.expectRevert(IHyperdriveFactory.InvalidDeployConfig.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.linkerCodeHash = oldLinkerCodeHash;

        // Ensure than an instance can't be deployed with a fee collector that
        // is set.
        vm.stopPrank();
        vm.startPrank(bob);
        address oldFeeCollector = config.feeCollector;
        config.feeCollector = address(0xdeadbeef);
        vm.expectRevert(IHyperdriveFactory.InvalidDeployConfig.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.feeCollector = oldFeeCollector;

        // Ensure than an instance can't be deployed with a governance address
        // that is set.
        vm.stopPrank();
        vm.startPrank(bob);
        address oldGovernance = config.governance;
        config.governance = address(0xdeadbeef);
        vm.expectRevert(IHyperdriveFactory.InvalidDeployConfig.selector);
        factory.deployAndInitialize(
            deployerCoordinator,
            config,
            extraData,
            10_000e18,
            0.02e18,
            new bytes(0)
        );
        config.governance = oldGovernance;
    }
}

contract HyperdriveFactoryBaseTest is HyperdriveTest {
    using FixedPointMath for *;

    HyperdriveFactory factory;

    address deployerCoordinator;
    address coreDeployer;
    address target0Deployer;
    address target1Deployer;
    address target2Deployer;
    address target3Deployer;

    IERC20 dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));

    IERC4626 pool1;
    IERC4626 pool2;

    uint256 aliceShares;

    uint256 constant APR = 0.01e18; // 1% apr
    uint256 constant CONTRIBUTION = 2_500e18;

    IHyperdrive.PoolDeployConfig config;

    function setUp() public virtual override __mainnet_fork(16_685_972) {
        alice = createUser("alice");
        bob = createUser("bob");

        vm.startPrank(deployer);

        // Deploy the ERC4626Hyperdrive factory and deployer.
        coreDeployer = address(new ERC4626HyperdriveCoreDeployer());
        target0Deployer = address(new ERC4626Target0Deployer());
        target1Deployer = address(new ERC4626Target1Deployer());
        target2Deployer = address(new ERC4626Target2Deployer());
        target3Deployer = address(new ERC4626Target3Deployer());

        deployerCoordinator = address(
            new ERC4626HyperdriveDeployerCoordinator(
                coreDeployer,
                target0Deployer,
                target1Deployer,
                target2Deployer,
                target3Deployer
            )
        );
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ForwarderFactory();
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
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees({
                    curve: 0.001e18,
                    flat: 0.0001e18,
                    governanceLP: 0.15e18,
                    governanceZombie: 0.03e18
                }),
                maxFees: IHyperdrive.Fees({
                    curve: 0.1e18,
                    flat: 0.01e18,
                    governanceLP: 0.15e18,
                    governanceZombie: 0.03e18
                }),
                linkerFactory: address(0xdeadbeef),
                linkerCodeHash: bytes32(uint256(0xdeadbabe))
            })
        );

        // Initialize this test's pool config.
        config = IHyperdrive.PoolDeployConfig({
            baseToken: dai,
            minimumShareReserves: 1e18,
            minimumTransactionAmount: 1e15,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: HyperdriveUtils.calculateTimeStretch(APR, 365 days),
            governance: address(0),
            feeCollector: address(0),
            fees: IHyperdrive.Fees(0.01e18, 0.001e18, 0.15e18, 0.03e18),
            linkerFactory: address(0),
            linkerCodeHash: bytes32(0)
        });

        vm.stopPrank();

        vm.prank(alice);
        factory.addDeployerCoordinator(deployerCoordinator);

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
            deployerCoordinator,
            config,
            abi.encode(address(pool), new address[](0)), // TODO: Add test with sweeps
            CONTRIBUTION,
            APR,
            new bytes(0)
        );

        vm.stopPrank();

        return hyperdrive;
    }
}

contract ERC4626FactoryMultiDeployTest is HyperdriveFactoryBaseTest {
    address deployerCoordinator1;

    function setUp() public override {
        super.setUp();
        // Deploy a new hyperdrive deployer to demonstrate multiple deployers can be used
        // with different hyperdrive implementations. The first implementation is ERC4626 so
        // the logic is the same, but future implementations may have different logic.
        deployerCoordinator1 = address(
            new ERC4626HyperdriveDeployerCoordinator(
                address(new ERC4626HyperdriveCoreDeployer()),
                address(new ERC4626Target0Deployer()),
                address(new ERC4626Target1Deployer()),
                address(new ERC4626Target2Deployer()),
                address(new ERC4626Target3Deployer())
            )
        );

        vm.prank(alice);
        factory.addDeployerCoordinator(deployerCoordinator1);
    }

    function test_hyperdriveFactoryDeploy_multiDeploy_multiPool() external {
        address charlie = createUser("charlie"); // External user 1
        address dan = createUser("dan"); // External user 2

        vm.startPrank(charlie);

        deal(address(dai), charlie, CONTRIBUTION);

        // 1. Charlie deploys factory with yDAI as yield source, hyperdrive deployer 1.

        dai.approve(address(factory), CONTRIBUTION);

        assertEq(dai.balanceOf(charlie), CONTRIBUTION);
        assertEq(dai.balanceOf(address(pool1)), 0);

        IHyperdrive hyperdrive1 = factory.deployAndInitialize(
            deployerCoordinator,
            config,
            abi.encode(address(pool1), new address[](0)),
            CONTRIBUTION,
            APR,
            new bytes(0)
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
            abi.encode(address(pool1), new address[](0)),
            0
        );

        assertEq(factory.getNumberOfInstances(), 1);
        assertEq(factory.getInstanceAtIndex(0), address(hyperdrive1));

        address[] memory instances = factory.getInstancesInRange(0, 0);
        assertEq(instances.length, 1);
        assertEq(instances[0], address(hyperdrive1));

        // 2. Charlie deploys factory with sDAI as yield source, hyperdrive deployer 2.

        deal(address(dai), charlie, CONTRIBUTION);

        dai.approve(address(factory), CONTRIBUTION);

        IHyperdrive hyperdrive2 = factory.deployAndInitialize(
            deployerCoordinator1,
            config,
            abi.encode(address(pool2), new address[](0)),
            CONTRIBUTION,
            APR,
            new bytes(0)
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
            abi.encode(address(pool2), new address[](0)),
            0
        );

        assertEq(factory.getNumberOfInstances(), 2);
        assertEq(factory.getInstanceAtIndex(0), address(hyperdrive1));
        assertEq(factory.getInstanceAtIndex(1), address(hyperdrive2));

        instances = factory.getInstancesInRange(0, 1);
        assertEq(instances.length, 2);
        assertEq(instances[0], address(hyperdrive1));
        assertEq(instances[1], address(hyperdrive2));

        // 3. Dan deploys factory with sDAI as yield source, hyperdrive deployer 1.

        deal(address(dai), dan, CONTRIBUTION);

        vm.startPrank(dan);

        dai.approve(address(factory), CONTRIBUTION);

        assertEq(dai.balanceOf(dan), CONTRIBUTION);
        assertEq(dai.balanceOf(address(pool2)), CONTRIBUTION); // From Charlie

        IHyperdrive hyperdrive3 = factory.deployAndInitialize(
            deployerCoordinator,
            config,
            abi.encode(address(pool2), new address[](0)),
            CONTRIBUTION,
            APR,
            new bytes(0)
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
            abi.encode(address(pool2), new address[](0)),
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

contract ERC4626InstanceGetterTest is HyperdriveFactoryBaseTest {
    function testFuzz_hyperdriveFactory_getNumberOfInstances(
        uint256 numberOfInstances
    ) external {
        address charlie = createUser("charlie");

        numberOfInstances = _bound(numberOfInstances, 1, 10);

        for (uint256 i; i < numberOfInstances; i++) {
            _deployInstance(charlie, address(pool1));
        }

        assertEq(factory.getNumberOfInstances(), numberOfInstances);
    }

    function testFuzz_hyperdriveFactory_getInstanceAtIndex(
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

contract DeployerCoordinatorGetterTest is HyperdriveTest {
    HyperdriveFactory factory;

    function setUp() public override {
        super.setUp();

        vm.stopPrank();

        address[] memory defaults = new address[](1);
        defaults[0] = bob;
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
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees({
                    curve: 0.001e18,
                    flat: 0.0001e18,
                    governanceLP: 0.15e18,
                    governanceZombie: 0.03e18
                }),
                maxFees: IHyperdrive.Fees({
                    curve: 0.1e18,
                    flat: 0.01e18,
                    governanceLP: 0.15e18,
                    governanceZombie: 0.03e18
                }),
                linkerFactory: address(0xdeadbeef),
                linkerCodeHash: bytes32(uint256(0xdeadbabe))
            })
        );
    }

    function testFuzz_hyperdriveFactory_getNumberOfDeployerCoordinators(
        uint256 numberOfDeployerCoordinators
    ) external {
        numberOfDeployerCoordinators = _bound(
            numberOfDeployerCoordinators,
            1,
            10
        );

        address[] memory deployerCoordinators = new address[](
            numberOfDeployerCoordinators
        );

        for (uint256 i; i < numberOfDeployerCoordinators; i++) {
            deployerCoordinators[i] = address(
                new ERC4626HyperdriveDeployerCoordinator(
                    address(new ERC4626HyperdriveCoreDeployer()),
                    address(new ERC4626Target0Deployer()),
                    address(new ERC4626Target1Deployer()),
                    address(new ERC4626Target2Deployer()),
                    address(new ERC4626Target3Deployer())
                )
            );

            vm.prank(alice);
            factory.addDeployerCoordinator(deployerCoordinators[i]);
        }

        assertEq(
            factory.getNumberOfDeployerCoordinators(),
            numberOfDeployerCoordinators
        );
    }

    function testFuzz_hyperdriveFactory_getDeployerCoordinatorAtIndex(
        uint256 numberOfDeployerCoordinators
    ) external {
        numberOfDeployerCoordinators = _bound(
            numberOfDeployerCoordinators,
            1,
            10
        );

        address[] memory deployerCoordinators = new address[](
            numberOfDeployerCoordinators
        );

        for (uint256 i; i < numberOfDeployerCoordinators; i++) {
            deployerCoordinators[i] = address(
                new ERC4626HyperdriveDeployerCoordinator(
                    address(new ERC4626HyperdriveCoreDeployer()),
                    address(new ERC4626Target0Deployer()),
                    address(new ERC4626Target1Deployer()),
                    address(new ERC4626Target2Deployer()),
                    address(new ERC4626Target3Deployer())
                )
            );

            vm.prank(alice);
            factory.addDeployerCoordinator(deployerCoordinators[i]);
        }

        for (uint256 i; i < numberOfDeployerCoordinators; i++) {
            assertEq(
                factory.getDeployerCoordinatorAtIndex(i),
                address(deployerCoordinators[i])
            );
        }
    }

    function testFuzz_hyperdriveFactory_getDeployerCoordinatorsInRange(
        uint256 numberOfDeployerCoordinators,
        uint256 startingIndex,
        uint256 endingIndex
    ) external {
        numberOfDeployerCoordinators = bound(
            numberOfDeployerCoordinators,
            1,
            10
        );
        startingIndex = bound(
            startingIndex,
            0,
            numberOfDeployerCoordinators - 1
        );
        endingIndex = bound(
            endingIndex,
            startingIndex,
            numberOfDeployerCoordinators - 1
        );

        address[] memory deployerCoordinators = new address[](
            numberOfDeployerCoordinators
        );

        for (uint256 i; i < numberOfDeployerCoordinators; i++) {
            deployerCoordinators[i] = address(
                new ERC4626HyperdriveDeployerCoordinator(
                    address(new ERC4626HyperdriveCoreDeployer()),
                    address(new ERC4626Target0Deployer()),
                    address(new ERC4626Target1Deployer()),
                    address(new ERC4626Target2Deployer()),
                    address(new ERC4626Target3Deployer())
                )
            );

            vm.prank(alice);
            factory.addDeployerCoordinator(deployerCoordinators[i]);
        }

        address[] memory deployerCoordinatorsArray = factory
            .getDeployerCoordinatorsInRange(startingIndex, endingIndex);

        assertEq(
            deployerCoordinatorsArray.length,
            endingIndex - startingIndex + 1
        );

        for (uint256 i; i < deployerCoordinatorsArray.length; i++) {
            assertEq(
                deployerCoordinatorsArray[i],
                address(deployerCoordinators[i + startingIndex])
            );
        }
    }
}

contract HyperdriveFactoryAddHyperdriveFactoryTest is HyperdriveTest {
    HyperdriveFactory factory;

    address deployerCoordinator0 = makeAddr("deployerCoordinator0");
    address deployerCoordinator1 = makeAddr("deployerCoordinator1");

    function setUp() public override {
        super.setUp();

        vm.stopPrank();

        address[] memory defaults = new address[](1);
        defaults[0] = bob;
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
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees({
                    curve: 0.001e18,
                    flat: 0.0001e18,
                    governanceLP: 0.15e18,
                    governanceZombie: 0.03e18
                }),
                maxFees: IHyperdrive.Fees({
                    curve: 0.1e18,
                    flat: 0.01e18,
                    governanceLP: 0.15e18,
                    governanceZombie: 0.03e18
                }),
                linkerFactory: address(0xdeadbeef),
                linkerCodeHash: bytes32(uint256(0xdeadbabe))
            })
        );
    }

    function test_hyperdriveFactory_addDeployerCoordinator_notGovernance()
        external
    {
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.addDeployerCoordinator(deployerCoordinator0);

        vm.prank(alice);
        factory.addDeployerCoordinator(deployerCoordinator0);
    }

    function test_hyperdriveFactory_addDeployerCoordinator_alreadyAdded()
        external
    {
        vm.startPrank(alice);
        factory.addDeployerCoordinator(deployerCoordinator0);

        vm.expectRevert(
            IHyperdriveFactory.DeployerCoordinatorAlreadyAdded.selector
        );
        factory.addDeployerCoordinator(deployerCoordinator0);
    }

    function test_hyperdriveFactory_addDeployerCoordinator() external {
        assertEq(factory.getNumberOfDeployerCoordinators(), 0);

        vm.prank(alice);
        factory.addDeployerCoordinator(deployerCoordinator0);

        assertEq(factory.getNumberOfDeployerCoordinators(), 1);
        assertEq(
            factory.getDeployerCoordinatorAtIndex(0),
            deployerCoordinator0
        );

        address[] memory deployerCoordinators = factory
            .getDeployerCoordinatorsInRange(0, 0);
        assertEq(deployerCoordinators.length, 1);
        assertEq(deployerCoordinators[0], deployerCoordinator0);

        vm.prank(alice);
        factory.addDeployerCoordinator(deployerCoordinator1);

        assertEq(factory.getNumberOfDeployerCoordinators(), 2);
        assertEq(
            factory.getDeployerCoordinatorAtIndex(0),
            deployerCoordinator0
        );
        assertEq(
            factory.getDeployerCoordinatorAtIndex(1),
            deployerCoordinator1
        );

        deployerCoordinators = factory.getDeployerCoordinatorsInRange(0, 1);
        assertEq(deployerCoordinators.length, 2);
        assertEq(deployerCoordinators[0], deployerCoordinator0);
        assertEq(deployerCoordinators[1], deployerCoordinator1);
    }
}

contract HyperdriveFactoryRemoveInstanceTest is HyperdriveTest {
    HyperdriveFactory factory;

    address deployerCoordinator0 = makeAddr("deployerCoordinator0");
    address deployerCoordinator1 = makeAddr("deployerCoordinator1");
    address deployerCoordinator2 = makeAddr("deployerCoordinator2");

    function setUp() public override {
        super.setUp();

        address[] memory defaults = new address[](1);
        defaults[0] = bob;
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
                minTimestretchAPR: 0.01e18,
                maxTimestretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees({
                    curve: 0.001e18,
                    flat: 0.0001e18,
                    governanceLP: 0.15e18,
                    governanceZombie: 0.03e18
                }),
                maxFees: IHyperdrive.Fees({
                    curve: 0.1e18,
                    flat: 0.01e18,
                    governanceLP: 0.15e18,
                    governanceZombie: 0.03e18
                }),
                linkerFactory: address(0xdeadbeef),
                linkerCodeHash: bytes32(uint256(0xdeadbabe))
            })
        );

        vm.startPrank(alice);
        factory.addDeployerCoordinator(deployerCoordinator0);
        factory.addDeployerCoordinator(deployerCoordinator1);
        factory.addDeployerCoordinator(deployerCoordinator2);
        vm.stopPrank();
    }

    function test_hyperdriveFactory_removeInstance_notGovernance() external {
        vm.expectRevert(IHyperdriveFactory.Unauthorized.selector);
        factory.removeDeployerCoordinator(deployerCoordinator0, 0);

        vm.startPrank(alice);
        factory.removeDeployerCoordinator(deployerCoordinator0, 0);
    }

    function test_hyperdriveFactory_removeDeployerCoordinator_notAdded()
        external
    {
        vm.startPrank(alice);

        vm.expectRevert(
            IHyperdriveFactory.DeployerCoordinatorNotAdded.selector
        );
        factory.removeDeployerCoordinator(
            address(makeAddr("not added address")),
            0
        );

        factory.removeDeployerCoordinator(deployerCoordinator0, 0);
    }

    function test_hyperdriveFactory_removeDeployerCoordinator_indexMismatch()
        external
    {
        vm.startPrank(alice);

        vm.expectRevert(
            IHyperdriveFactory.DeployerCoordinatorIndexMismatch.selector
        );
        factory.removeDeployerCoordinator(deployerCoordinator0, 1);

        factory.removeDeployerCoordinator(deployerCoordinator0, 0);
    }

    function test_hyperdriveFactory_removeDeployerCoordinator() external {
        assertEq(factory.getNumberOfDeployerCoordinators(), 3);
        assertEq(
            factory.getDeployerCoordinatorAtIndex(0),
            deployerCoordinator0
        );
        assertEq(
            factory.getDeployerCoordinatorAtIndex(1),
            deployerCoordinator1
        );
        assertEq(
            factory.getDeployerCoordinatorAtIndex(2),
            deployerCoordinator2
        );

        address[] memory deployerCoordinators = factory
            .getDeployerCoordinatorsInRange(0, 2);
        assertEq(deployerCoordinators.length, 3);
        assertEq(deployerCoordinators[0], deployerCoordinator0);
        assertEq(deployerCoordinators[1], deployerCoordinator1);
        assertEq(deployerCoordinators[2], deployerCoordinator2);

        assertEq(factory.isDeployerCoordinator(deployerCoordinator0), true);
        assertEq(factory.isDeployerCoordinator(deployerCoordinator1), true);
        assertEq(factory.isDeployerCoordinator(deployerCoordinator2), true);

        vm.prank(alice);
        factory.removeDeployerCoordinator(deployerCoordinator0, 0);

        // NOTE: Demonstrate that array order is NOT preserved after removal.

        assertEq(factory.getNumberOfDeployerCoordinators(), 2);
        assertEq(
            factory.getDeployerCoordinatorAtIndex(0),
            deployerCoordinator2
        );
        assertEq(
            factory.getDeployerCoordinatorAtIndex(1),
            deployerCoordinator1
        );

        deployerCoordinators = factory.getDeployerCoordinatorsInRange(0, 1);
        assertEq(deployerCoordinators.length, 2);
        assertEq(deployerCoordinators[0], deployerCoordinator2);
        assertEq(deployerCoordinators[1], deployerCoordinator1);

        assertEq(factory.isDeployerCoordinator(deployerCoordinator0), false);
        assertEq(factory.isDeployerCoordinator(deployerCoordinator1), true);
        assertEq(factory.isDeployerCoordinator(deployerCoordinator2), true);
    }
}
