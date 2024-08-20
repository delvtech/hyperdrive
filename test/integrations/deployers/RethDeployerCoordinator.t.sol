// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../../contracts/src/interfaces/IHyperdriveDeployerCoordinator.sol";
import { IHyperdriveFactory } from "../../../contracts/src/interfaces/IHyperdriveFactory.sol";
import { HyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/HyperdriveDeployerCoordinator.sol";
import { RETHHyperdriveCoreDeployer } from "../../../contracts/src/deployers/reth/RETHHyperdriveCoreDeployer.sol";
import { RETHTarget0Deployer } from "../../../contracts/src/deployers/reth/RETHTarget0Deployer.sol";
import { RETHTarget1Deployer } from "../../../contracts/src/deployers/reth/RETHTarget1Deployer.sol";
import { RETHTarget2Deployer } from "../../../contracts/src/deployers/reth/RETHTarget2Deployer.sol";
import { RETHTarget3Deployer } from "../../../contracts/src/deployers/reth/RETHTarget3Deployer.sol";
import { RETHTarget4Deployer } from "../../../contracts/src/deployers/reth/RETHTarget4Deployer.sol";
import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { MockRocketPool } from "../../../contracts/test/MockRocketPool.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { DeployerCoordinatorTest, MockHyperdriveDeployerCoordinator } from "./DeployerCoordinator.t.sol";
import { Lib } from "../../utils/Lib.sol";

contract RethDeployerCoordinatorTest is DeployerCoordinatorTest {
    using FixedPointMath for *;
    using Lib for *;

    MockRocketPool private vault;

    function setUp() public override {
        super.setUp();

        // Deploy a base token and RETH vault. Encode the vault into extra
        // data.
        vm.stopPrank();
        vm.startPrank(alice);
        baseToken = new ERC20Mintable(
            "Base Token",
            "BASE",
            18,
            address(0),
            false,
            type(uint256).max
        );
        vault = new MockRocketPool(0.05e18, alice, true, type(uint256).max);

        // Create a deployment config.
        config = testDeployConfig(0.05e18, 365 days);
        config.baseToken = IERC20(address(baseToken));
        config.vaultSharesToken = IERC20(address(vault));

        // Deploy the factory.
        factory = IHyperdriveFactory(
            new HyperdriveFactory(
                HyperdriveFactory.FactoryConfig({
                    governance: alice,
                    deployerCoordinatorManager: celine,
                    hyperdriveGovernance: bob,
                    feeCollector: feeCollector,
                    sweepCollector: sweepCollector,
                    checkpointRewarder: address(0),
                    defaultPausers: new address[](0),
                    checkpointDurationResolution: 1 hours,
                    minCheckpointDuration: 8 hours,
                    maxCheckpointDuration: 1 days,
                    minPositionDuration: 7 days,
                    maxPositionDuration: 10 * 365 days,
                    minCircuitBreakerDelta: 0.15e18,
                    maxCircuitBreakerDelta: 0.6e18,
                    minFixedAPR: 0.001e18,
                    maxFixedAPR: 0.5e18,
                    minTimeStretchAPR: 0.005e18,
                    maxTimeStretchAPR: 0.5e18,
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
                }),
                "HyperdriveFactory"
            )
        );

        // Deploy the coordinator.
        coordinator = new MockHyperdriveDeployerCoordinator(
            COORDINATOR_NAME,
            address(factory),
            address(new RETHHyperdriveCoreDeployer()),
            address(new RETHTarget0Deployer()),
            address(new RETHTarget1Deployer()),
            address(new RETHTarget2Deployer()),
            address(new RETHTarget3Deployer()),
            address(new RETHTarget4Deployer())
        );

        // Start a prank as the factory address. This is the default address
        // that should be used for deploying Hyperdrive instances.
        vm.stopPrank();
        vm.startPrank(address(factory));
    }

    function test_initialize_success_asBase() external override {
        // TODO: Implement this test.
    }

    function test_initialize_success_asShares() external override {
        // TODO: Implement this test.
    }
}
