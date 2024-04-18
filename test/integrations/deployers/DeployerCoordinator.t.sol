// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "contracts/src/interfaces/IHyperdriveDeployerCoordinator.sol";
import { HyperdriveDeployerCoordinator } from "contracts/src/deployers/HyperdriveDeployerCoordinator.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { Lib } from "test/utils/Lib.sol";

contract MockHyperdriveDeployerCoordinator is HyperdriveDeployerCoordinator {
    string public constant override name = "MockHyperdriveDeployerCoordinator";

    bool internal _checkMessageValueStatus = true;
    bool internal _checkPoolConfigStatus = true;

    constructor(
        address _factory,
        address _coreDeployer,
        address _target0Deployer,
        address _target1Deployer,
        address _target2Deployer,
        address _target3Deployer,
        address _target4Deployer
    )
        HyperdriveDeployerCoordinator(
            _factory,
            _coreDeployer,
            _target0Deployer,
            _target1Deployer,
            _target2Deployer,
            _target3Deployer,
            _target4Deployer
        )
    {}

    function setCheckMessageValueStatus(bool _status) external {
        _checkMessageValueStatus = _status;
    }

    function setCheckPoolConfigStatus(bool _status) external {
        _checkPoolConfigStatus = _status;
    }

    function _prepareInitialize(
        IHyperdrive _hyperdrive,
        address _lp,
        uint256 _contribution,
        IHyperdrive.Options memory _options
    ) internal override returns (uint256) {
        // If base is the deposit asset, transfer base from the LP and approve
        // the Hyperdrive pool.
        if (_options.asBase) {
            IERC20 baseToken = IERC20(_hyperdrive.baseToken());
            baseToken.transferFrom(_lp, address(this), _contribution);
            baseToken.approve(address(_hyperdrive), _contribution);
        }
        // Otherwise, transfer vault shares from the LP and approve the
        // Hyperdrive pool.
        else {
            IERC20 vault = IERC20(_hyperdrive.vaultSharesToken());
            vault.transferFrom(_lp, address(this), _contribution);
            vault.approve(address(_hyperdrive), _contribution);
        }

        return 0;
    }

    function _checkMessageValue() internal view override {
        require(
            _checkMessageValueStatus,
            "MockDeployerCoordinator: invalid message value"
        );
    }

    function _checkPoolConfig(
        IHyperdrive.PoolDeployConfig memory
    ) internal view override {
        require(
            _checkPoolConfigStatus,
            "MockDeployerCoordinator: invalid config"
        );
    }

    function _getInitialVaultSharePrice(
        IHyperdrive.PoolDeployConfig memory,
        bytes memory
    ) internal pure override returns (uint256) {
        return ONE;
    }
}

abstract contract DeployerCoordinatorTest is HyperdriveTest {
    using FixedPointMath for *;
    using Lib for *;

    bytes32 constant DEPLOYMENT_ID = bytes32(uint256(0xdeadbeef));
    bytes32 constant SALT = bytes32(uint256(0xdecafc0ffee));

    IHyperdrive.PoolDeployConfig internal config;

    address internal factory;
    MockERC4626 private vault;
    MockHyperdriveDeployerCoordinator internal coordinator;

    function test_deployTarget_failure_invalidSender() external {
        // Attempt to deploy a target0 instance with an invalid sender. This
        // should revert since the sender is not the factory address.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.SenderIsNotFactory.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 0, SALT);
    }

    function test_deployTarget_failure_deploymentAlreadyExists() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 0, SALT);

        // Attempt to deploy a target0 instance again.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.DeploymentAlreadyExists.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 0, SALT);
    }

    function test_deployTarget_failure_deploymentDoesNotExist() external {
        // Attempt to deploy a target1 instance without first deploying target0.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.DeploymentDoesNotExist.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 1, SALT);
    }

    function test_deployTarget_failure_mismatchedConfig() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 0, SALT);

        // Attempt to deploy a target1 instance with a mismatched config.
        config.baseToken = IERC20(address(0));
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.MismatchedConfig.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 1, SALT);
    }

    function test_deployTarget_failure_mismatchedExtraData() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 0, SALT);

        // Attempt to deploy a target1 instance with mismatched extra data.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.MismatchedExtraData.selector
        );
        coordinator.deployTarget(
            DEPLOYMENT_ID,
            config,
            abi.encode(address(0xdeadbeef)),
            1,
            SALT
        );
    }

    function test_deployTarget_failure_invalidCheckPoolConfigTarget0()
        external
    {
        // Attempt to deploy a target0 instance with an invalid config.
        coordinator.setCheckPoolConfigStatus(false);
        vm.expectRevert("MockDeployerCoordinator: invalid config");
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 0, SALT);
    }

    function test_deployTarget_failure_invalidCheckPoolConfigTarget1()
        external
    {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 0, SALT);

        // Attempt to deploy a target1 instance with an invalid config.
        coordinator.setCheckPoolConfigStatus(false);
        vm.expectRevert("MockDeployerCoordinator: invalid config");
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 1, SALT);
    }

    function test_deployTarget_failure_target1AlreadyDeployed() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 0, SALT);

        // Deploy a target1 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 1, SALT);

        // Attempt to deploy target1 again.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.TargetAlreadyDeployed.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 1, SALT);
    }

    function test_deployTarget_failure_target2AlreadyDeployed() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 0, SALT);

        // Deploy a target2 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 2, SALT);

        // Attempt to deploy target2 again.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.TargetAlreadyDeployed.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 2, SALT);
    }

    function test_deployTarget_failure_target3AlreadyDeployed() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 0, SALT);

        // Deploy a target3 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 3, SALT);

        // Attempt to deploy target3 again.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.TargetAlreadyDeployed.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 3, SALT);
    }

    function test_deployTarget_failure_target4AlreadyDeployed() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 0, SALT);

        // Deploy a target4 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 4, SALT);

        // Attempt to deploy target4 again.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.TargetAlreadyDeployed.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 4, SALT);
    }

    function test_deployTarget_failure_invalidTargetIndex() external {
        // Deploy a target0 instance.
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 0, SALT);

        // Attempt to deploy a 5th target instance.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.InvalidTargetIndex.selector
        );
        coordinator.deployTarget(DEPLOYMENT_ID, config, new bytes(0), 5, SALT);
    }

    function test_deployTarget_success() external {
        // Deploy a target0 instance.
        address target0 = coordinator.deployTarget(
            DEPLOYMENT_ID,
            config,
            new bytes(0),
            0,
            SALT
        );

        // Ensure that the deployment was configured correctly.
        HyperdriveDeployerCoordinator.Deployment memory deployment = coordinator
            .deployments(DEPLOYMENT_ID);
        assertEq(deployment.configHash, keccak256(abi.encode(config)));
        assertEq(deployment.extraDataHash, keccak256(new bytes(0)));
        assertEq(deployment.initialSharePrice, ONE);
        assertEq(deployment.target0, address(target0));

        // Deploy the other target instances.
        address[] memory targets = new address[](4);
        for (uint256 i = 1; i < 5; i++) {
            targets[i - 1] = coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Ensure that the deployment was configured correctly.
        deployment = coordinator.deployments(DEPLOYMENT_ID);
        assertEq(deployment.target1, targets[0]);
        assertEq(deployment.target2, targets[1]);
        assertEq(deployment.target3, targets[2]);
        assertEq(deployment.target4, targets[3]);
    }

    function test_deploy_failure_invalidSender() external {
        // Deploy the target instances and a Hyperdrive instance.
        for (uint256 i = 0; i < 5; i++) {
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Attempt to deploy a Hyperdrive instance with an invalid sender. This
        // should revert since the sender is not the factory address.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.SenderIsNotFactory.selector
        );
        coordinator.deploy(DEPLOYMENT_ID, config, new bytes(0), SALT);
    }

    function test_deploy_failure_hyperdriveAlreadyDeployed() external {
        // Deploy the target instances and a Hyperdrive instance.
        for (uint256 i = 0; i < 5; i++) {
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }
        coordinator.deploy(DEPLOYMENT_ID, config, new bytes(0), SALT);

        // Attempt to deploy a Hyperdrive instance again.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.HyperdriveAlreadyDeployed.selector
        );
        coordinator.deploy(DEPLOYMENT_ID, config, new bytes(0), SALT);
    }

    function test_deploy_failure_deploymentDoesNotExist() external {
        // Attempt to deploy a Hyperdrive instance without deploying any of the
        // target instances.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.DeploymentDoesNotExist.selector
        );
        coordinator.deploy(DEPLOYMENT_ID, config, new bytes(0), SALT);
    }

    function test_deploy_failure_incompleteDeploymentTarget1() external {
        // Deploy all of the target instances except for target1.
        for (uint256 i = 0; i < 5; i++) {
            if (i == 1) {
                continue;
            }
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Attempt to deploy a Hyperdrive instance.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.IncompleteDeployment.selector
        );
        coordinator.deploy(DEPLOYMENT_ID, config, new bytes(0), SALT);
    }

    function test_deploy_failure_incompleteDeploymentTarget2() external {
        // Deploy all of the target instances except for target2.
        for (uint256 i = 0; i < 5; i++) {
            if (i == 2) {
                continue;
            }
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Attempt to deploy a Hyperdrive instance.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.IncompleteDeployment.selector
        );
        coordinator.deploy(DEPLOYMENT_ID, config, new bytes(0), SALT);
    }

    function test_deploy_failure_incompleteDeploymentTarget3() external {
        // Deploy all of the target instances except for target3.
        for (uint256 i = 0; i < 5; i++) {
            if (i == 3) {
                continue;
            }
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Attempt to deploy a Hyperdrive instance.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.IncompleteDeployment.selector
        );
        coordinator.deploy(DEPLOYMENT_ID, config, new bytes(0), SALT);
    }

    function test_deploy_failure_incompleteDeploymentTarget4() external {
        // Deploy all of the target instances except for target4.
        for (uint256 i = 0; i < 5; i++) {
            if (i == 4) {
                continue;
            }
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Attempt to deploy a Hyperdrive instance.
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.IncompleteDeployment.selector
        );
        coordinator.deploy(DEPLOYMENT_ID, config, new bytes(0), SALT);
    }

    function test_deploy_failure_mismatchedConfig() external {
        // Deploy all of the target instances.
        for (uint256 i = 0; i < 5; i++) {
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Attempt to deploy a Hyperdrive instance with a mismatched config.
        config.fees.curve = config.fees.curve + 1;
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.MismatchedConfig.selector
        );
        coordinator.deploy(DEPLOYMENT_ID, config, new bytes(0), SALT);
    }

    function test_deploy_failure_mismatchedExtraData() external {
        // Deploy all of the target instances.
        for (uint256 i = 0; i < 5; i++) {
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Attempt to deploy a Hyperdrive instance with mismatched extra data.
        bytes memory extraData = abi.encode(bytes32(uint256(0xdeadbeef)));
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.MismatchedExtraData.selector
        );
        coordinator.deploy(DEPLOYMENT_ID, config, extraData, SALT);
    }

    function test_deploy_failure_invalidCheckPoolConfig() external {
        // Deploy all of the target instances.
        for (uint256 i = 0; i < 5; i++) {
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Attempt to deploy a Hyperdrive instance with an invalid pool config.
        coordinator.setCheckPoolConfigStatus(false);
        vm.expectRevert("MockDeployerCoordinator: invalid config");
        coordinator.deploy(DEPLOYMENT_ID, config, new bytes(0), SALT);
    }

    function test_deploy_success() external {
        // Deploy all of the target instances.
        address[] memory targets = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            targets[i] = coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Deploy a Hyperdrive instance.
        address hyperdrive = coordinator.deploy(
            DEPLOYMENT_ID,
            config,
            new bytes(0),
            SALT
        );

        // Ensure that the deployment was configured correctly.
        HyperdriveDeployerCoordinator.Deployment memory deployment = coordinator
            .deployments(DEPLOYMENT_ID);
        assertEq(deployment.configHash, keccak256(abi.encode(config)));
        assertEq(deployment.extraDataHash, keccak256(new bytes(0)));
        assertEq(deployment.initialSharePrice, ONE);
        assertEq(deployment.target0, targets[0]);
        assertEq(deployment.target1, targets[1]);
        assertEq(deployment.target2, targets[2]);
        assertEq(deployment.target3, targets[3]);
        assertEq(deployment.target4, targets[4]);
        assertEq(deployment.hyperdrive, hyperdrive);
    }

    function test_initialize_failure_invalidSender() external {
        // Deploy all of the target instances and the hyperdrive instance.
        for (uint256 i = 0; i < 5; i++) {
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }
        coordinator.deploy(DEPLOYMENT_ID, config, new bytes(0), SALT);

        // Attempt to initialize with an invalid sender. This should revert
        // since the sender is not the factory address.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.SenderIsNotFactory.selector
        );
        uint256 contribution = 100_000e18;
        coordinator.initialize(
            DEPLOYMENT_ID,
            msg.sender,
            contribution,
            0.05e18,
            IHyperdrive.Options({
                asBase: true,
                destination: msg.sender,
                extraData: new bytes(0)
            })
        );
    }

    function test_initialize_failure_hyperdriveIsNotDeployed() external {
        // Deploy all of the target instances.
        for (uint256 i = 0; i < 5; i++) {
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Initialization should fail since the hyperdrive instance isn't
        // deployed.
        uint256 contribution = 100_000e18;
        vm.expectRevert(
            IHyperdriveDeployerCoordinator.HyperdriveIsNotDeployed.selector
        );
        coordinator.initialize(
            DEPLOYMENT_ID,
            msg.sender,
            contribution,
            0.05e18,
            IHyperdrive.Options({
                asBase: true,
                destination: msg.sender,
                extraData: new bytes(0)
            })
        );
    }

    function test_initialize_failure_checkMessageValue() external {
        // Deploy all of the target instances.
        for (uint256 i = 0; i < 5; i++) {
            coordinator.deployTarget(
                DEPLOYMENT_ID,
                config,
                new bytes(0),
                i,
                SALT
            );
        }

        // Deploy a Hyperdrive instance.
        address hyperdrive = coordinator.deploy(
            DEPLOYMENT_ID,
            config,
            new bytes(0),
            SALT
        );

        // Initialization should fail if `_checkMessageValue` fails.
        coordinator.setCheckMessageValueStatus(false);
        uint256 contribution = 100_000e18;
        baseToken.mint(contribution);
        baseToken.approve(hyperdrive, contribution);
        vm.expectRevert();
        coordinator.initialize(
            DEPLOYMENT_ID,
            msg.sender,
            contribution,
            0.05e18,
            IHyperdrive.Options({
                asBase: true,
                destination: msg.sender,
                extraData: new bytes(0)
            })
        );
    }

    function test_initialize_success_asBase() external virtual;

    function test_initialize_success_asShares() external virtual;
}
