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
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
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

    event FeeCollectorUpdated(address newFeeCollector);

    /// @notice Emitted when governance is transferred.
    event GovernanceUpdated(address governance);

    /// @notice Emitted when a new Hyperdrive deployer is added.
    event HyperdriveDeployerAdded(address hyperdriveDeployer);

    /// @notice Emitted when a Hyperdrive deployer is remove.
    event HyperdriveDeployerRemoved(address hyperdriveDeployer);

    /// @notice Emitted when the Hyperdrive governance address is updated.
    event HyperdriveGovernanceUpdated(address hyperdriveGovernance);

    /// @notice Emitted when the Hyperdrive implementation is updated.
    event ImplementationUpdated(address newDeployer);

    /// @notice Emitted when the linker factory is updated.
    event LinkerFactoryUpdated(address newLinkerFactory);

    /// @notice Emitted when the linker code hash is updated.
    event LinkerCodeHashUpdated(bytes32 newLinkerCodeHash);

    /// @notice Emitted when the checkpoint duration resolution is updated.
    event CheckpointDurationResolutionUpdated(
        uint256 newCheckpointDurationResolution
    );

    /// @notice Emitted when the maximum checkpoint duration is updated.
    event MaxCheckpointDurationUpdated(uint256 newMaxCheckpointDuration);

    /// @notice Emitted when the minimum checkpoint duration is updated.
    event MinCheckpointDurationUpdated(uint256 newMinCheckpointDuration);

    /// @notice Emitted when the maximum position duration is updated.
    event MaxPositionDurationUpdated(uint256 newMaxPositionDuration);

    /// @notice Emitted when the minimum position duration is updated.
    event MinPositionDurationUpdated(uint256 newMinPositionDuration);

    /// @notice Emitted when the max fees are updated.
    event MaxFeesUpdated(IHyperdrive.Fees newMaxFees);

    /// @notice Emitted when the min fees are updated.
    event MinFeesUpdated(IHyperdrive.Fees newMinFees);

    function setUp() public override {
        super.setUp();

        // Deploy the factory.
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
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
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
        vm.expectRevert(IHyperdrive.InvalidMinCheckpointDuration.selector);
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
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum
        // checkpoint duration that isn't a multiple of the checkpoint duration
        // resolution.
        vm.expectRevert(IHyperdrive.InvalidMinCheckpointDuration.selector);
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
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // checkpoint duration that is less than the minimum checkpoint
        // duration.
        vm.expectRevert(IHyperdrive.InvalidMaxCheckpointDuration.selector);
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
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // checkpoint duration that isn't a multiple of the checkpoint duration
        // resolution.
        vm.expectRevert(IHyperdrive.InvalidMaxCheckpointDuration.selector);
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
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum position
        // duration that is less than the maximum checkpoint duration.
        vm.expectRevert(IHyperdrive.InvalidMinPositionDuration.selector);
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
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum
        // position duration that isn't a multiple of the checkpoint duration
        // resolution.
        vm.expectRevert(IHyperdrive.InvalidMinPositionDuration.selector);
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
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // position duration that is less than the minimum position duration.
        vm.expectRevert(IHyperdrive.InvalidMaxPositionDuration.selector);
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
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // position duration that isn't a multiple of the checkpoint duration
        // resolution.
        vm.expectRevert(IHyperdrive.InvalidMaxPositionDuration.selector);
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
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // curve fee greater than 1.
        vm.expectRevert(IHyperdrive.InvalidMaxFees.selector);
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
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(2 * ONE, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // flat fee greater than 1.
        vm.expectRevert(IHyperdrive.InvalidMaxFees.selector);
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
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, 2 * ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // governance LP fee greater than 1.
        vm.expectRevert(IHyperdrive.InvalidMaxFees.selector);
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
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, 2 * ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a maximum
        // governance zombie fee greater than 1.
        vm.expectRevert(IHyperdrive.InvalidMaxFees.selector);
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
                minFees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, ONE, 2 * ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum
        // curve fee greater than the maximum curve fee.
        vm.expectRevert(IHyperdrive.InvalidMinFees.selector);
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
                minFees: IHyperdrive.Fees(ONE, 0, 0, 0),
                maxFees: IHyperdrive.Fees(0, ONE, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum
        // flat fee greater than the maximum flat fee.
        vm.expectRevert(IHyperdrive.InvalidMinFees.selector);
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
                minFees: IHyperdrive.Fees(0, ONE, 0, 0),
                maxFees: IHyperdrive.Fees(ONE, 0, ONE, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum
        // governance LP fee greater than the maximum governance LP fee.
        vm.expectRevert(IHyperdrive.InvalidMinFees.selector);
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
                minFees: IHyperdrive.Fees(0, 0, ONE, 0),
                maxFees: IHyperdrive.Fees(ONE, ONE, 0, ONE),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        // Ensure that the factory can't be constructed with a minimum
        // governance zombie fee greater than the maximum governance zombie fee.
        vm.expectRevert(IHyperdrive.InvalidMinFees.selector);
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
        vm.prank(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateGovernance(newGovernance);

        // Ensure that governance was updated successfully and that the correct
        // event was emitted.
        vm.prank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit GovernanceUpdated(newGovernance);
        factory.updateGovernance(newGovernance);
        assertEq(factory.governance(), newGovernance);
    }

    function test_updateHyperdriveGovernance() external {
        address newHyperdriveGovernance = address(0xdeadbeef);

        // Ensure that hyperdrive governance can't be updated by someone other
        // than the current governance.
        vm.prank(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateHyperdriveGovernance(newHyperdriveGovernance);

        // Ensure that hyperdrive governance was updated successfully and that
        // the correct event was emitted.
        vm.prank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit HyperdriveGovernanceUpdated(newHyperdriveGovernance);
        factory.updateHyperdriveGovernance(newHyperdriveGovernance);
        assertEq(factory.hyperdriveGovernance(), newHyperdriveGovernance);
    }

    function test_updateLinkerFactory() external {
        address newLinkerFactory = address(0xdeadbeef);

        // Ensure that the linker factory can't be updated by someone other
        // than the current governance.
        vm.prank(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateLinkerFactory(newLinkerFactory);

        // Ensure that the linker factory was updated successfully and that the
        // correct event was emitted.
        vm.prank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit LinkerFactoryUpdated(newLinkerFactory);
        factory.updateLinkerFactory(newLinkerFactory);
        assertEq(factory.linkerFactory(), newLinkerFactory);
    }

    function test_updateLinkerCodeHash() external {
        bytes32 newLinkerCodeHash = bytes32(uint256(0xdeadbeef));

        // Ensure that the linker code hash can't be updated by someone other
        // than the current governance.
        vm.prank(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateLinkerCodeHash(newLinkerCodeHash);

        // Ensure that the linker code hash was updated successfully and that
        // the correct event was emitted.
        vm.prank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit LinkerCodeHashUpdated(newLinkerCodeHash);
        factory.updateLinkerCodeHash(newLinkerCodeHash);
        assertEq(factory.linkerCodeHash(), newLinkerCodeHash);
    }

    function test_updateFeeCollector() external {
        address newFeeCollector = address(0xdeadbeef);

        // Ensure that the fee collector can't be updated by someone other than
        // the current governance.
        vm.prank(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateFeeCollector(newFeeCollector);

        // Ensure that the fee collector was updated successfully and that the
        // correct event was emitted.
        vm.prank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit FeeCollectorUpdated(newFeeCollector);
        factory.updateFeeCollector(newFeeCollector);
        assertEq(factory.feeCollector(), newFeeCollector);
    }

    function test_updateCheckpointDurationResolution() external {
        uint256 newCheckpointDurationResolution = 30 minutes;

        // Ensure that the checkpoint duration resolution can't be updated by
        // someone other than the current governance.
        vm.prank(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateCheckpointDurationResolution(
            newCheckpointDurationResolution
        );

        // Ensure that the checkpoint duration resolution can't be set to a
        // value that doesn't divide the min checkpoint duration.
        vm.prank(factory.governance());
        factory.updateMinCheckpointDuration(3 hours);
        factory.updateMaxCheckpointDuration(4 hours);
        factory.updateMinPositionDuration(4 hours);
        factory.updateMaxPositionDuration(4 hours);
        vm.expectRevert(
            IHyperdrive.InvalidCheckpointDurationResolution.selector
        );
        factory.updateCheckpointDurationResolution(2 hours);

        // Ensure that the checkpoint duration resolution can't be set to a
        // value that doesn't divide the max checkpoint duration.
        vm.prank(factory.governance());
        factory.updateMinCheckpointDuration(3 hours);
        factory.updateMaxCheckpointDuration(4 hours);
        factory.updateMinPositionDuration(6 hours);
        factory.updateMaxPositionDuration(6 hours);
        vm.expectRevert(
            IHyperdrive.InvalidCheckpointDurationResolution.selector
        );
        factory.updateCheckpointDurationResolution(3 hours);

        // Ensure that the checkpoint duration resolution can't be set to a
        // value that doesn't divide the min position duration.
        vm.prank(factory.governance());
        factory.updateMinCheckpointDuration(3 hours);
        factory.updateMaxCheckpointDuration(3 hours);
        factory.updateMinPositionDuration(4 hours);
        factory.updateMaxPositionDuration(6 hours);
        vm.expectRevert(
            IHyperdrive.InvalidCheckpointDurationResolution.selector
        );
        factory.updateCheckpointDurationResolution(3 hours);

        // Ensure that the checkpoint duration resolution can't be set to a
        // value that doesn't divide the max position duration.
        vm.prank(factory.governance());
        factory.updateMinCheckpointDuration(3 hours);
        factory.updateMaxCheckpointDuration(3 hours);
        factory.updateMinPositionDuration(3 hours);
        factory.updateMaxPositionDuration(4 hours);
        vm.expectRevert(
            IHyperdrive.InvalidCheckpointDurationResolution.selector
        );
        factory.updateCheckpointDurationResolution(3 hours);

        // Ensure that the fee collector was updated successfully and that the
        // correct event was emitted.
        vm.prank(factory.governance());
        factory.updateMinCheckpointDuration(8 hours);
        factory.updateMaxCheckpointDuration(1 days);
        factory.updateMinPositionDuration(7 days);
        factory.updateMaxPositionDuration(10 * 365 days);
        vm.expectEmit(true, true, true, true);
        emit CheckpointDurationResolutionUpdated(
            newCheckpointDurationResolution
        );
        factory.updateFeeCollector(newCheckpointDurationResolution);
        assertEq(
            factory.checkpointDurationResolution(),
            newCheckpointDurationResolution
        );
    }

    function test_updateMaxCheckpointDuration() external {
        uint256 newMaxCheckpointDuration = 2 days;

        // Ensure that the max checkpoint duration can't be updated by someone
        // other than the current governance.
        vm.prank(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateMaxCheckpointDuration(newMaxCheckpointDuration);

        // Ensure that the max checkpoint duration can't be set to a value
        // less than the min checkpoint duration.
        vm.prank(factory.governance());
        vm.expectRevert(IHyperdrive.InvalidMaxCheckpointDuration.selector);
        factory.updateMaxCheckpointDuration(
            factory.minCheckpointDuration() - 1
        );

        // Ensure that the max checkpoint duration can't be set to a value
        // that isn't a multiple of the checkpoint duration resolution.
        vm.prank(factory.governance());
        vm.expectRevert(IHyperdrive.InvalidMaxCheckpointDuration.selector);
        factory.updateMaxCheckpointDuration(
            factory.minCheckpointDuration() +
                factory.checkpointDurationResolution() /
                2
        );

        // Ensure that the max checkpoint duration can't be set to a value
        // greater than the min position duration.
        vm.prank(factory.governance());
        vm.expectRevert(IHyperdrive.InvalidMaxCheckpointDuration.selector);
        factory.updateMaxCheckpointDuration(factory.minPositionDuration() + 1);

        // Ensure that the max checkpoint duration was updated successfully and
        // that the correct event was emitted.
        vm.prank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit MaxCheckpointDurationUpdated(newMaxCheckpointDuration);
        factory.updateMaxCheckpointDuration(newMaxCheckpointDuration);
        assertEq(factory.maxCheckpointDuration(), newMaxCheckpointDuration);
    }

    function test_updateMinCheckpointDuration() external {
        uint256 newMinCheckpointDuration = 12 hours;

        // Ensure that the min checkpoint duration can't be updated by someone
        // other than the current governance.
        vm.prank(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateMinCheckpointDuration(newMinCheckpointDuration);

        // Ensure that the min checkpoint duration can't be set to a value
        // less than the checkpoint duration resolution.
        vm.prank(factory.governance());
        vm.expectRevert(IHyperdrive.InvalidMinCheckpointDuration.selector);
        factory.updateMinCheckpointDuration(
            factory.checkpointDurationResolution() - 1
        );

        // Ensure that the min checkpoint duration can't be set to a value
        // that isn't a multiple of the checkpoint duration resolution.
        vm.prank(factory.governance());
        vm.expectRevert(IHyperdrive.InvalidMinCheckpointDuration.selector);
        factory.updateMinCheckpointDuration(
            factory.minCheckpointDuration() +
                factory.checkpointDurationResolution() /
                2
        );

        // Ensure that the min checkpoint duration can't be set to a value
        // greater than the max checkpoint duration.
        vm.prank(factory.governance());
        vm.expectRevert(IHyperdrive.InvalidMinCheckpointDuration.selector);
        factory.updateMinCheckpointDuration(
            factory.maxCheckpointDuration() + 1
        );

        // Ensure that the min checkpoint duration was updated successfully and
        // that the correct event was emitted.
        vm.prank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit MinCheckpointDurationUpdated(newMinCheckpointDuration);
        factory.updateMinCheckpointDuration(newMinCheckpointDuration);
        assertEq(factory.minCheckpointDuration(), newMinCheckpointDuration);
    }

    function test_updateMaxPositionDuration() external {
        uint256 newMaxPositionDuration = 30 * 365 days;

        // Ensure that the max position duration can't be updated by someone
        // other than the current governance.
        vm.prank(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateMaxPositionDuration(newMaxPositionDuration);

        // Ensure that the max position duration can't be set to a value
        // less than the min position duration.
        vm.prank(factory.governance());
        vm.expectRevert(IHyperdrive.InvalidMaxPositionDuration.selector);
        factory.updateMaxPositionDuration(factory.minPositionDuration() - 1);

        // Ensure that the max position duration can't be set to a value
        // that isn't a multiple of the checkpoint duration resolution.
        vm.prank(factory.governance());
        vm.expectRevert(IHyperdrive.InvalidMaxPositionDuration.selector);
        factory.updateMaxPositionDuration(
            factory.minPositionDuration() +
                factory.checkpointDurationResolution() /
                2
        );

        // Ensure that the max position duration was updated successfully and
        // that the correct event was emitted.
        vm.prank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit MaxPositionDurationUpdated(newMaxPositionDuration);
        factory.updateMaxPositionDuration(newMaxPositionDuration);
        assertEq(factory.maxPositionDuration(), newMaxPositionDuration);
    }

    function test_updateMinPositionDuration() external {
        uint256 newMinPositionDuration = 3 days;

        // Ensure that the min position duration can't be updated by someone
        // other than the current governance.
        vm.prank(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateMinPositionDuration(newMinPositionDuration);

        // Ensure that the min position duration can't be set to a value
        // less than the max checkpoint duration.
        vm.prank(factory.governance());
        vm.expectRevert(IHyperdrive.InvalidMinPositionDuration.selector);
        factory.updateMinPositionDuration(
            factory.checkpointDurationResolution() - 1
        );

        // Ensure that the min position duration can't be set to a value that
        // isn't a multiple of the checkpoint duration resolution.
        vm.prank(factory.governance());
        vm.expectRevert(IHyperdrive.InvalidMinPositionDuration.selector);
        factory.updateMinPositionDuration(
            factory.maxCheckpointDuration() +
                factory.checkpointDurationResolution() /
                2
        );

        // Ensure that the min position duration can't be set to a value greater
        // than the max position duration.
        vm.prank(factory.governance());
        vm.expectRevert(IHyperdrive.InvalidMinPositionDuration.selector);
        factory.updateMinPositionDuration(factory.maxPositionDuration() + 1);

        // Ensure that the min position duration was updated successfully and
        // that the correct event was emitted.
        vm.prank(factory.governance());
        vm.expectEmit(true, true, true, true);
        emit MinPositionDurationUpdated(newMinPositionDuration);
        factory.updateMinPositionDuration(newMinPositionDuration);
        assertEq(factory.minPositionDuration(), newMinPositionDuration);
    }

    // FIXME
    function test_updateMaxFees() external {}

    // FIXME
    function test_updateMinFees() external {}

    // FIXME
    function test_updateDefaultPausers() external {}

    // FIXME
    function test_addHyperdriveDeployer() external {}

    // FIXME
    function test_removeHyperdriveDeployer() external {}
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
                feeCollector: bob,
                fees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(0, 0, 0, 0),
                defaultPausers: defaults,
                linkerFactory: address(forwarderFactory),
                linkerCodeHash: forwarderFactory.ERC20LINK_HASH()
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
            governance: alice,
            feeCollector: bob,
            fees: IHyperdrive.Fees(0, 0, 0, 0),
            linkerFactory: address(forwarderFactory),
            linkerCodeHash: forwarderFactory.ERC20LINK_HASH()
        });

        vm.stopPrank();

        vm.prank(alice);
        factory.addHyperdriveDeployer(deployerCoordinator);

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
        factory.addHyperdriveDeployer(deployerCoordinator1);
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

contract HyperdriveDeployerGetterTest is HyperdriveTest {
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
                feeCollector: bob,
                defaultPausers: defaults,
                fees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(0, 0, 0, 0),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );
    }

    function testFuzz_hyperdriveFactory_getNumberOfHyperdriveDeployers(
        uint256 numberOfHyperdriveDeployers
    ) external {
        numberOfHyperdriveDeployers = _bound(
            numberOfHyperdriveDeployers,
            1,
            10
        );

        address[] memory hyperdriveDeployers = new address[](
            numberOfHyperdriveDeployers
        );

        for (uint256 i; i < numberOfHyperdriveDeployers; i++) {
            hyperdriveDeployers[i] = address(
                new ERC4626HyperdriveDeployerCoordinator(
                    address(new ERC4626HyperdriveCoreDeployer()),
                    address(new ERC4626Target0Deployer()),
                    address(new ERC4626Target1Deployer()),
                    address(new ERC4626Target2Deployer()),
                    address(new ERC4626Target3Deployer())
                )
            );

            vm.prank(alice);
            factory.addHyperdriveDeployer(hyperdriveDeployers[i]);
        }

        assertEq(
            factory.getNumberOfHyperdriveDeployers(),
            numberOfHyperdriveDeployers
        );
    }

    function testFuzz_hyperdriveFactory_getHyperdriveDeployerAtIndex(
        uint256 numberOfHyperdriveDeployers
    ) external {
        numberOfHyperdriveDeployers = _bound(
            numberOfHyperdriveDeployers,
            1,
            10
        );

        address[] memory hyperdriveDeployers = new address[](
            numberOfHyperdriveDeployers
        );

        for (uint256 i; i < numberOfHyperdriveDeployers; i++) {
            hyperdriveDeployers[i] = address(
                new ERC4626HyperdriveDeployerCoordinator(
                    address(new ERC4626HyperdriveCoreDeployer()),
                    address(new ERC4626Target0Deployer()),
                    address(new ERC4626Target1Deployer()),
                    address(new ERC4626Target2Deployer()),
                    address(new ERC4626Target3Deployer())
                )
            );

            vm.prank(alice);
            factory.addHyperdriveDeployer(hyperdriveDeployers[i]);
        }

        for (uint256 i; i < numberOfHyperdriveDeployers; i++) {
            assertEq(
                factory.getHyperdriveDeployerAtIndex(i),
                address(hyperdriveDeployers[i])
            );
        }
    }

    function testFuzz_hyperdriveFactory_getHyperdriveDeployersInRange(
        uint256 numberOfHyperdriveDeployers,
        uint256 startingIndex,
        uint256 endingIndex
    ) external {
        numberOfHyperdriveDeployers = bound(numberOfHyperdriveDeployers, 1, 10);
        startingIndex = bound(
            startingIndex,
            0,
            numberOfHyperdriveDeployers - 1
        );
        endingIndex = bound(
            endingIndex,
            startingIndex,
            numberOfHyperdriveDeployers - 1
        );

        address[] memory hyperdriveDeployers = new address[](
            numberOfHyperdriveDeployers
        );

        for (uint256 i; i < numberOfHyperdriveDeployers; i++) {
            hyperdriveDeployers[i] = address(
                new ERC4626HyperdriveDeployerCoordinator(
                    address(new ERC4626HyperdriveCoreDeployer()),
                    address(new ERC4626Target0Deployer()),
                    address(new ERC4626Target1Deployer()),
                    address(new ERC4626Target2Deployer()),
                    address(new ERC4626Target3Deployer())
                )
            );

            vm.prank(alice);
            factory.addHyperdriveDeployer(hyperdriveDeployers[i]);
        }

        address[] memory hyperdriveDeployersArray = factory
            .getHyperdriveDeployersInRange(startingIndex, endingIndex);

        assertEq(
            hyperdriveDeployersArray.length,
            endingIndex - startingIndex + 1
        );

        for (uint256 i; i < hyperdriveDeployersArray.length; i++) {
            assertEq(
                hyperdriveDeployersArray[i],
                address(hyperdriveDeployers[i + startingIndex])
            );
        }
    }
}

contract HyperdriveFactoryAddHyperdriveFactoryTest is HyperdriveTest {
    HyperdriveFactory factory;

    address hyperdriveDeployer0 = makeAddr("hyperdriveDeployer0");
    address hyperdriveDeployer1 = makeAddr("hyperdriveDeployer1");

    function setUp() public override {
        super.setUp();

        vm.stopPrank();

        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                fees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(0, 0, 0, 0),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );
    }

    function test_hyperdriveFactory_addHyperdriveDeployer_notGovernance()
        external
    {
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.addHyperdriveDeployer(hyperdriveDeployer0);

        vm.prank(alice);
        factory.addHyperdriveDeployer(hyperdriveDeployer0);
    }

    function test_hyperdriveFactory_addHyperdriveDeployer_alreadyAdded()
        external
    {
        vm.startPrank(alice);
        factory.addHyperdriveDeployer(hyperdriveDeployer0);

        vm.expectRevert(IHyperdrive.HyperdriveDeployerAlreadyAdded.selector);
        factory.addHyperdriveDeployer(hyperdriveDeployer0);
    }

    function test_hyperdriveFactory_addHyperdriveDeployer() external {
        assertEq(factory.getNumberOfHyperdriveDeployers(), 0);

        vm.prank(alice);
        factory.addHyperdriveDeployer(hyperdriveDeployer0);

        assertEq(factory.getNumberOfHyperdriveDeployers(), 1);
        assertEq(factory.getHyperdriveDeployerAtIndex(0), hyperdriveDeployer0);

        address[] memory hyperdriveDeployers = factory
            .getHyperdriveDeployersInRange(0, 0);
        assertEq(hyperdriveDeployers.length, 1);
        assertEq(hyperdriveDeployers[0], hyperdriveDeployer0);

        vm.prank(alice);
        factory.addHyperdriveDeployer(hyperdriveDeployer1);

        assertEq(factory.getNumberOfHyperdriveDeployers(), 2);
        assertEq(factory.getHyperdriveDeployerAtIndex(0), hyperdriveDeployer0);
        assertEq(factory.getHyperdriveDeployerAtIndex(1), hyperdriveDeployer1);

        hyperdriveDeployers = factory.getHyperdriveDeployersInRange(0, 1);
        assertEq(hyperdriveDeployers.length, 2);
        assertEq(hyperdriveDeployers[0], hyperdriveDeployer0);
        assertEq(hyperdriveDeployers[1], hyperdriveDeployer1);
    }
}

contract HyperdriveFactoryRemoveInstanceTest is HyperdriveTest {
    HyperdriveFactory factory;

    address hyperdriveDeployer0 = makeAddr("hyperdriveDeployer0");
    address hyperdriveDeployer1 = makeAddr("hyperdriveDeployer1");
    address hyperdriveDeployer2 = makeAddr("hyperdriveDeployer2");

    function setUp() public override {
        super.setUp();

        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                fees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(0, 0, 0, 0),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        vm.startPrank(alice);
        factory.addHyperdriveDeployer(hyperdriveDeployer0);
        factory.addHyperdriveDeployer(hyperdriveDeployer1);
        factory.addHyperdriveDeployer(hyperdriveDeployer2);
        vm.stopPrank();
    }

    function test_hyperdriveFactory_removeInstance_notGovernance() external {
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.removeHyperdriveDeployer(hyperdriveDeployer0, 0);

        vm.startPrank(alice);
        factory.removeHyperdriveDeployer(hyperdriveDeployer0, 0);
    }

    function test_hyperdriveFactory_removeHyperdriveDeployer_notAdded()
        external
    {
        vm.startPrank(alice);

        vm.expectRevert(IHyperdrive.HyperdriveDeployerNotAdded.selector);
        factory.removeHyperdriveDeployer(
            address(makeAddr("not added address")),
            0
        );

        factory.removeHyperdriveDeployer(hyperdriveDeployer0, 0);
    }

    function test_hyperdriveFactory_removeHyperdriveDeployer_indexMismatch()
        external
    {
        vm.startPrank(alice);

        vm.expectRevert(IHyperdrive.HyperdriveDeployerIndexMismatch.selector);
        factory.removeHyperdriveDeployer(hyperdriveDeployer0, 1);

        factory.removeHyperdriveDeployer(hyperdriveDeployer0, 0);
    }

    function test_hyperdriveFactory_removeHyperdriveDeployer() external {
        assertEq(factory.getNumberOfHyperdriveDeployers(), 3);
        assertEq(factory.getHyperdriveDeployerAtIndex(0), hyperdriveDeployer0);
        assertEq(factory.getHyperdriveDeployerAtIndex(1), hyperdriveDeployer1);
        assertEq(factory.getHyperdriveDeployerAtIndex(2), hyperdriveDeployer2);

        address[] memory hyperdriveDeployers = factory
            .getHyperdriveDeployersInRange(0, 2);
        assertEq(hyperdriveDeployers.length, 3);
        assertEq(hyperdriveDeployers[0], hyperdriveDeployer0);
        assertEq(hyperdriveDeployers[1], hyperdriveDeployer1);
        assertEq(hyperdriveDeployers[2], hyperdriveDeployer2);

        assertEq(factory.isHyperdriveDeployer(hyperdriveDeployer0), true);
        assertEq(factory.isHyperdriveDeployer(hyperdriveDeployer1), true);
        assertEq(factory.isHyperdriveDeployer(hyperdriveDeployer2), true);

        vm.prank(alice);
        factory.removeHyperdriveDeployer(hyperdriveDeployer0, 0);

        // NOTE: Demonstrate that array order is NOT preserved after removal.

        assertEq(factory.getNumberOfHyperdriveDeployers(), 2);
        assertEq(factory.getHyperdriveDeployerAtIndex(0), hyperdriveDeployer2);
        assertEq(factory.getHyperdriveDeployerAtIndex(1), hyperdriveDeployer1);

        hyperdriveDeployers = factory.getHyperdriveDeployersInRange(0, 1);
        assertEq(hyperdriveDeployers.length, 2);
        assertEq(hyperdriveDeployers[0], hyperdriveDeployer2);
        assertEq(hyperdriveDeployers[1], hyperdriveDeployer1);

        assertEq(factory.isHyperdriveDeployer(hyperdriveDeployer0), false);
        assertEq(factory.isHyperdriveDeployer(hyperdriveDeployer1), true);
        assertEq(factory.isHyperdriveDeployer(hyperdriveDeployer2), true);
    }
}
