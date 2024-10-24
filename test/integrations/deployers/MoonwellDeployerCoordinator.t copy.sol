// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../../contracts/src/interfaces/IHyperdriveDeployerCoordinator.sol";
import { IHyperdriveFactory } from "../../../contracts/src/interfaces/IHyperdriveFactory.sol";
import { HyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/HyperdriveDeployerCoordinator.sol";
import { ERC4626HyperdriveCoreDeployer } from "../../../contracts/src/deployers/erc4626/ERC4626HyperdriveCoreDeployer.sol";
import { ERC4626Target0Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target1Deployer.sol";
import { ERC4626Target2Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target2Deployer.sol";
import { ERC4626Target3Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target3Deployer.sol";
import { ERC4626Target4Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target4Deployer.sol";
import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "../../../contracts/test/MockERC4626.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { DeployerCoordinatorTest, MockHyperdriveDeployerCoordinator } from "./DeployerCoordinator.t.sol";
import { Lib } from "../../utils/Lib.sol";

contract ERC4626DeployerCoordinatorTest is DeployerCoordinatorTest {
    using FixedPointMath for *;
    using Lib for *;

    MockERC4626 private vault;

    function setUp() public override {
        super.setUp();

        // Deploy a base token and ERC4626 vault. Encode the vault into extra
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
        vault = new MockERC4626(
            baseToken,
            "Vault",
            "VAULT",
            18,
            address(0),
            false,
            type(uint256).max
        );

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
            address(new ERC4626HyperdriveCoreDeployer()),
            address(new ERC4626Target0Deployer()),
            address(new ERC4626Target1Deployer()),
            address(new ERC4626Target2Deployer()),
            address(new ERC4626Target3Deployer()),
            address(new ERC4626Target4Deployer())
        );

        // Start a prank as the factory address. This is the default address
        // that should be used for deploying Hyperdrive instances.
        vm.stopPrank();
        vm.startPrank(address(factory));
    }

    function test_initialize_success_asBase() external override {
        // Deploy all of the target instances.
        for (uint256 i = 0; i < coordinator.getNumberOfTargets(); i++) {
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Deploy a Hyperdrive instance.
        IHyperdrive hyperdrive = IHyperdrive(
            coordinator.deployHyperdrive(
                DEPLOYMENT_ID,
                HYPERDRIVE_NAME,
                config,
                new bytes(0),
                SALT
            )
        );

        // Initialization should succeed with Alice as the initializer.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 contribution = 100_000e18;
        baseToken.mint(contribution);
        baseToken.approve(address(coordinator), contribution);
        vm.stopPrank();
        vm.startPrank(address(factory));
        uint256 lpShares = coordinator.initialize(
            DEPLOYMENT_ID,
            alice,
            contribution,
            0.05e18,
            IHyperdrive.Options({
                asBase: true,
                destination: alice,
                extraData: new bytes(0)
            })
        );

        // Ensure the initializer received the correct amount of LP shares.
        assertEq(
            lpShares,
            contribution.divDown(
                hyperdrive.getPoolConfig().initialVaultSharePrice
            ) - 2 * hyperdrive.getPoolConfig().minimumShareReserves
        );
        assertEq(lpShares, hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice));
    }

    function test_initialize_success_asShares() external override {
        // Deploy all of the target instances.
        for (uint256 i = 0; i < coordinator.getNumberOfTargets(); i++) {
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Deploy a Hyperdrive instance.
        IHyperdrive hyperdrive = IHyperdrive(
            coordinator.deployHyperdrive(
                DEPLOYMENT_ID,
                HYPERDRIVE_NAME,
                config,
                new bytes(0),
                SALT
            )
        );

        // Initialization should succeed.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 contribution = 100_000e18;
        baseToken.mint(contribution);
        baseToken.approve(address(vault), contribution);
        uint256 contributionShares = vault.deposit(contribution, alice);
        vault.approve(address(coordinator), contributionShares);
        vm.stopPrank();
        vm.startPrank(address(factory));
        uint256 lpShares = coordinator.initialize(
            DEPLOYMENT_ID,
            alice,
            contributionShares,
            0.05e18,
            IHyperdrive.Options({
                asBase: false,
                destination: alice,
                extraData: new bytes(0)
            })
        );

        // Ensure the initializer received the correct amount of LP shares.
        assertEq(
            lpShares,
            contributionShares -
                2 *
                hyperdrive.getPoolConfig().minimumShareReserves
        );
    }
}
