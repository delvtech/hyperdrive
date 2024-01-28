// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "contracts/src/interfaces/IHyperdriveDeployerCoordinator.sol";
import { HyperdriveDeployerCoordinator } from "contracts/src/deployers/HyperdriveDeployerCoordinator.sol";
import { ERC4626HyperdriveCoreDeployer } from "contracts/src/deployers/erc4626/ERC4626HyperdriveCoreDeployer.sol";
import { ERC4626HyperdriveDeployerCoordinator } from "contracts/src/deployers/erc4626/ERC4626HyperdriveDeployerCoordinator.sol";
import { ERC4626Target0Deployer } from "contracts/src/deployers/erc4626/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "contracts/src/deployers/erc4626/ERC4626Target1Deployer.sol";
import { ERC4626Target2Deployer } from "contracts/src/deployers/erc4626/ERC4626Target2Deployer.sol";
import { ERC4626Target3Deployer } from "contracts/src/deployers/erc4626/ERC4626Target3Deployer.sol";
import { ERC4626Target4Deployer } from "contracts/src/deployers/erc4626/ERC4626Target4Deployer.sol";
import { ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";

contract DeployerCoordinatorTest is HyperdriveTest {
    bytes32 constant DEPLOYMENT_ID = bytes32(uint256(0xdeadbeef));
    bytes32 constant SALT = bytes32(uint256(0xdecafc0ffee));

    bytes internal extraData;
    IHyperdrive.PoolDeployConfig internal config;

    MockERC4626 internal vault;
    ERC4626HyperdriveDeployerCoordinator internal coordinator;

    function setUp() public override {
        super.setUp();

        // Deploy a base token and ERC4626 vault. Encode the vault into extra
        // data.
        vm.stopPrank();
        vm.startPrank(alice);
        ERC20Mintable baseToken = new ERC20Mintable(
            "Base Token",
            "BASE",
            18,
            address(0),
            false
        );
        vault = new MockERC4626(
            baseToken,
            "Vault",
            "VAULT",
            18,
            address(0),
            false
        );
        extraData = abi.encode(vault);

        // Create a deployment config.
        config = testDeployConfig(0.05e18, 365 days);
        config.baseToken = IERC20(address(baseToken));

        // Deploy the coordinator.
        coordinator = new ERC4626HyperdriveDeployerCoordinator(
            address(new ERC4626HyperdriveCoreDeployer()),
            address(new ERC4626Target0Deployer()),
            address(new ERC4626Target1Deployer()),
            address(new ERC4626Target2Deployer()),
            address(new ERC4626Target3Deployer()),
            address(new ERC4626Target4Deployer())
        );
    }

    function test_deployTarget_failure_deploymentAlreadyExists() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 0, SALT);

        // Attempt to deploy a target0 instance again.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.DeploymentAlreadyExists.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 0, SALT);
    }

    function test_deployTarget_failure_deploymentDoesNotExist() external {
        // Attempt to deploy a target1 instance without first deploying target0.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.DeploymentDoesNotExist.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 1, SALT);
    }

    function test_deployTarget_failure_mismatchedConfig() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 0, SALT);

        // Attempt to deploy a target1 instance with a mismatched config.
        config.baseToken = IERC20(address(0));
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.MismatchedConfig.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 1, SALT);
    }

    function test_deployTarget_failure_mismatchedExtraData() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 0, SALT);

        // Attempt to deploy a target1 instance with mismatched extra data.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.MismatchedExtraData.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 1, SALT);
    }

    function test_deployTarget_failure_invalidCheckPoolConfig() external {
        // Attempt to deploy a target0 instance with an invalid config.
        config.fees.curve = 2e18;
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.InvalidFeeAmounts.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 0, SALT);
    }

    function test_deployTarget_failure_target1AlreadyDeployed() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 0, SALT);

        // Deploy a target1 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 1, SALT);

        // Attempt to deploy target1 again.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.TargetAlreadyDeployed.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 1, SALT);
    }

    function test_deployTarget_failure_target2AlreadyDeployed() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 0, SALT);

        // Deploy a target2 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 2, SALT);

        // Attempt to deploy target2 again.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.TargetAlreadyDeployed.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 2, SALT);
    }

    function test_deployTarget_failure_target3AlreadyDeployed() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 0, SALT);

        // Deploy a target3 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 3, SALT);

        // Attempt to deploy target3 again.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.TargetAlreadyDeployed.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 3, SALT);
    }

    function test_deployTarget_failure_target4AlreadyDeployed() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 0, SALT);

        // Deploy a target4 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 4, SALT);

        // Attempt to deploy target4 again.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.TargetAlreadyDeployed.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 4, SALT);
    }

    function test_deployTarget_failure_invalidTargetIndex() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 0, SALT);

        // Attempt to deploy a 5th target instance.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.InvalidTargetIndex.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, extraData, 5, SALT);
    }

    function test_deployTarget_success() external {
        // Deploy a target0 instance.
        address target0 = coordinator.deployTarget(
            DEPLOYMENT_ID,
            config,
            extraData,
            0,
            SALT
        );

        // Ensure that the deployment was configured correctly.
        HyperdriveDeployerCoordinator.Deployment memory deployment = coordinator
            .deployments(alice, DEPLOYMENT_ID);
        assertEq(deployment.configHash, keccak256(abi.encode(config)));
        assertEq(deployment.extraDataHash, keccak256(extraData));
        assertEq(deployment.initialSharePrice, vault.convertToAssets(ONE));
        assertEq(deployment.target0, address(target0));

        // Deploy a target1 instance.
        address target1 = coordinator.deployTarget(
            DEPLOYMENT_ID,
            config,
            extraData,
            1,
            SALT
        );

        // Deploy a target2 instance.
        address target2 = coordinator.deployTarget(
            DEPLOYMENT_ID,
            config,
            extraData,
            2,
            SALT
        );

        // Deploy a target3 instance.
        address target3 = coordinator.deployTarget(
            DEPLOYMENT_ID,
            config,
            extraData,
            3,
            SALT
        );

        // Deploy a target4 instance.
        address target4 = coordinator.deployTarget(
            DEPLOYMENT_ID,
            config,
            extraData,
            4,
            SALT
        );

        // Ensure that the deployment was configured correctly.
        deployment = coordinator.deployments(alice, DEPLOYMENT_ID);
        assertEq(deployment.target1, address(target1));
        assertEq(deployment.target2, address(target2));
        assertEq(deployment.target3, address(target3));
        assertEq(deployment.target4, address(target4));
    }

    // FIXME: Finish these

    function test_deploy_hyperdriveAlreadyDeployed() external {}

    function test_deploy_deploymentDoesNotExist() external {}

    function test_deploy_incompleteDeployment() external {}

    function test_deploy_mismatchedConfig() external {}

    function test_deploy_mismatchedExtraData() external {}

    function test_deploy_invalidCheckPoolConfig() external {}

    function test_deploy_success() external {}
}
