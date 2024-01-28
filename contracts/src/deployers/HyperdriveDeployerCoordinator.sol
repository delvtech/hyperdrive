// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveCoreDeployer } from "../interfaces/IHyperdriveCoreDeployer.sol";
import { IHyperdriveDeployerCoordinator } from "../interfaces/IHyperdriveDeployerCoordinator.sol";
import { IHyperdriveTargetDeployer } from "../interfaces/IHyperdriveTargetDeployer.sol";

/// @author DELV
/// @title HyperdriveDeployerCoordinator
/// @notice This Hyperdrive deployer coordinates the process of deploying the
///         Hyperdrive system utilizing several child deployers.
/// @dev We use multiple deployers to avoid the maximum code size.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveDeployerCoordinator is
    IHyperdriveDeployerCoordinator
{
    struct Deployment {
        /// @dev The hash of the config used in this deployment. This is used to
        ///      ensure that the config is the same across all deployments in
        ///      the batch.
        bytes32 configHash;
        /// @dev The hash of the extra data passed to the child deployers. This
        ///      is used to ensure that the extra data is the same across all
        ///      deployments in the batch.
        bytes32 extraDataHash;
        /// @dev The initial share price used in the first part of this
        ///      deployment. This is used to ensure that the initial share price
        ///      is the same across all deployments in the batch.
        uint256 initialSharePrice;
        /// @dev The address of the Hyperdrive entrypoint.
        address hyperdrive;
        /// @dev The address of the HyperdriveTarget0 contract.
        address target0;
        /// @dev The address of the HyperdriveTarget1 contract.
        address target1;
        /// @dev The address of the HyperdriveTarget2 contract.
        address target2;
        /// @dev The address of the HyperdriveTarget3 contract.
        address target3;
        /// @dev The address of the HyperdriveTarget4 contract.
        address target4;
    }

    /// @notice The contract used to deploy new instances of Hyperdrive.
    address public immutable coreDeployer;

    /// @notice The contract used to deploy new instances of HyperdriveTarget0.
    address public immutable target0Deployer;

    /// @notice The contract used to deploy new instances of HyperdriveTarget1.
    address public immutable target1Deployer;

    /// @notice The contract used to deploy new instances of HyperdriveTarget2.
    address public immutable target2Deployer;

    /// @notice The contract used to deploy new instances of HyperdriveTarget3.
    address public immutable target3Deployer;

    /// @notice The contract used to deploy new instances of HyperdriveTarget4.
    address public immutable target4Deployer;

    /// @notice A mapping from deployer to deployment ID to deployment.
    mapping(address => mapping(bytes32 => Deployment)) internal _deployments;

    /// @notice Instantiates the deployer coordinator.
    /// @param _coreDeployer The core deployer.
    /// @param _target0Deployer The target0 deployer.
    /// @param _target1Deployer The target1 deployer.
    /// @param _target2Deployer The target2 deployer.
    /// @param _target4Deployer The target4 deployer.
    constructor(
        address _coreDeployer,
        address _target0Deployer,
        address _target1Deployer,
        address _target2Deployer,
        address _target3Deployer,
        address _target4Deployer
    ) {
        coreDeployer = _coreDeployer;
        target0Deployer = _target0Deployer;
        target1Deployer = _target1Deployer;
        target2Deployer = _target2Deployer;
        target3Deployer = _target3Deployer;
        target4Deployer = _target4Deployer;
    }

    /// @notice Deploys a Hyperdrive instance with the given parameters.
    /// @param _deploymentId The ID of the deployment.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains the pool and sweep targets.
    /// @param _salt The create2 salt used to deploy Hyperdrive.
    /// @return The address of the newly deployed ERC4626Hyperdrive Instance.
    function deploy(
        bytes32 _deploymentId,
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory _extraData,
        bytes32 _salt
    ) external returns (address) {
        // Ensure that the Hyperdrive entrypoint has not already been deployed.
        Deployment memory deployment = _deployments[msg.sender][_deploymentId];
        if (deployment.hyperdrive != address(0)) {
            revert IHyperdriveDeployerCoordinator.HyperdriveAlreadyDeployed();
        }

        // Ensure that the deployment is not a fresh deployment. We can check
        // this by ensuring that the config hash is set.
        if (deployment.configHash == bytes32(0)) {
            revert IHyperdriveDeployerCoordinator.DeploymentDoesNotExist();
        }

        // Ensure that all of the targets have been deployed.
        if (
            deployment.target0 == address(0) ||
            deployment.target1 == address(0) ||
            deployment.target2 == address(0) ||
            deployment.target3 == address(0) ||
            deployment.target4 == address(0)
        ) {
            revert IHyperdriveDeployerCoordinator.IncompleteDeployment();
        }

        // Ensure that the provided config matches the config hash.
        if (keccak256(abi.encode(_deployConfig)) != deployment.configHash) {
            revert IHyperdriveDeployerCoordinator.MismatchedConfig();
        }

        // Ensure that the provided extra data matches the extra data hash.
        if (keccak256(_extraData) != deployment.extraDataHash) {
            revert IHyperdriveDeployerCoordinator.MismatchedExtraData();
        }

        // Check the pool configuration to ensure that it's a valid
        // configuration for this instance. This was already done when deploying
        // target0, but we check again as a precaution in case the check relies
        // on state that can change.
        _checkPoolConfig(_deployConfig);

        // Convert the deploy config into the pool config and set the initial
        // vault share price.
        IHyperdrive.PoolConfig memory config = _copyPoolConfig(_deployConfig);
        config.initialVaultSharePrice = deployment.initialSharePrice;

        // Deploy the Hyperdrive instance and add it to the deployment struct.
        address hyperdrive = IHyperdriveCoreDeployer(coreDeployer).deploy(
            config,
            _extraData,
            deployment.target0,
            deployment.target1,
            deployment.target2,
            deployment.target3,
            deployment.target4,
            _salt
        );
        _deployments[msg.sender][_deploymentId].hyperdrive = hyperdrive;

        return hyperdrive;
    }

    /// @notice Deploys a Hyperdrive target instance with the given parameters.
    /// @dev As a convention, target0 must be deployed first. After this, the
    ///      targets can be deployed in any order.
    /// @param _deploymentId The ID of the deployment.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains the pool and sweep targets.
    /// @param _targetIndex The index of the target to deploy.
    /// @param _salt The create2 salt used to deploy the target.
    /// @return target The address of the newly deployed target instance.
    function deployTarget(
        bytes32 _deploymentId,
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory _extraData,
        uint256 _targetIndex,
        bytes32 _salt
    ) external returns (address target) {
        // If the target index is 0, then we're deploying the target0 instance.
        // By convention, this target must be deployed first, and as part of the
        // deployment of target0, we will register the deployment in the state.
        if (_targetIndex == 0) {
            // Ensure that the deployment is a fresh deployment. We can check this
            // by ensuring that the config hash is not set.
            if (
                _deployments[msg.sender][_deploymentId].configHash != bytes32(0)
            ) {
                revert IHyperdriveDeployerCoordinator.DeploymentAlreadyExists();
            }

            // Check the pool configuration to ensure that it's a valid
            // configuration for this instance.
            _checkPoolConfig(_deployConfig);

            // Get the initial share price and the hashes of the config and extra
            // data.
            uint256 initialSharePrice = _getInitialVaultSharePrice(_extraData);
            bytes32 configHash = keccak256(abi.encode(_deployConfig));
            bytes32 extraDataHash = keccak256(_extraData);

            // Convert the deploy config into the pool config and set the initial
            // vault share price.
            IHyperdrive.PoolConfig memory config_ = _copyPoolConfig(
                _deployConfig
            );
            config_.initialVaultSharePrice = initialSharePrice;

            // Deploy the target0 contract.
            target = IHyperdriveTargetDeployer(target0Deployer).deploy(
                config_,
                _extraData,
                _salt
            );

            // Store the deployment.
            _deployments[msg.sender][_deploymentId].configHash = configHash;
            _deployments[msg.sender][_deploymentId]
                .extraDataHash = extraDataHash;
            _deployments[msg.sender][_deploymentId]
                .initialSharePrice = initialSharePrice;
            _deployments[msg.sender][_deploymentId].target0 = target;

            return target;
        }

        // Ensure that the deployment is not a fresh deployment. We can check
        // this by ensuring that the config hash is set.
        if (_deployments[msg.sender][_deploymentId].configHash == bytes32(0)) {
            revert IHyperdriveDeployerCoordinator.DeploymentDoesNotExist();
        }

        // Ensure that the provided config matches the config hash.
        if (
            keccak256(abi.encode(_deployConfig)) !=
            _deployments[msg.sender][_deploymentId].configHash
        ) {
            revert IHyperdriveDeployerCoordinator.MismatchedConfig();
        }

        // Ensure that the provided extra data matches the extra data hash.
        if (
            keccak256(_extraData) !=
            _deployments[msg.sender][_deploymentId].extraDataHash
        ) {
            revert IHyperdriveDeployerCoordinator.MismatchedExtraData();
        }

        // Check the pool configuration to ensure that it's a valid
        // configuration for this instance. This was already done when deploying
        // target0, but we check again as a precaution in case the check relies
        // on state that can change.
        _checkPoolConfig(_deployConfig);

        // Convert the deploy config into the pool config and set the initial
        // vault share price.
        IHyperdrive.PoolConfig memory config = _copyPoolConfig(_deployConfig);
        config.initialVaultSharePrice = _deployments[msg.sender][_deploymentId]
            .initialSharePrice;

        // If the target index is greater than 0, then we're deploying one of
        // the other target instances. We don't allow targets to be deployed
        // more than once, and their addresses are stored in the deployment
        // state.
        if (_targetIndex == 1) {
            if (_deployments[msg.sender][_deploymentId].target1 != address(0)) {
                revert IHyperdriveDeployerCoordinator.TargetAlreadyDeployed();
            }
            target = IHyperdriveTargetDeployer(target1Deployer).deploy(
                config,
                _extraData,
                _salt
            );
            _deployments[msg.sender][_deploymentId].target1 = target;
        } else if (_targetIndex == 2) {
            if (_deployments[msg.sender][_deploymentId].target2 != address(0)) {
                revert IHyperdriveDeployerCoordinator.TargetAlreadyDeployed();
            }
            target = IHyperdriveTargetDeployer(target2Deployer).deploy(
                config,
                _extraData,
                _salt
            );
            _deployments[msg.sender][_deploymentId].target2 = target;
        } else if (_targetIndex == 3) {
            if (_deployments[msg.sender][_deploymentId].target3 != address(0)) {
                revert IHyperdriveDeployerCoordinator.TargetAlreadyDeployed();
            }
            target = IHyperdriveTargetDeployer(target3Deployer).deploy(
                config,
                _extraData,
                _salt
            );
            _deployments[msg.sender][_deploymentId].target3 = target;
        } else if (_targetIndex == 4) {
            if (_deployments[msg.sender][_deploymentId].target4 != address(0)) {
                revert IHyperdriveDeployerCoordinator.TargetAlreadyDeployed();
            }
            target = IHyperdriveTargetDeployer(target4Deployer).deploy(
                config,
                _extraData,
                _salt
            );
            _deployments[msg.sender][_deploymentId].target4 = target;
        } else {
            revert IHyperdriveDeployerCoordinator.InvalidTargetIndex();
        }

        return target;
    }

    /// @notice Gets the deployment specified by the deployer and deployment ID.
    /// @param _deployer The deployer.
    /// @param _deploymentId The deployment ID.
    /// @return The deployment.
    function deployments(
        address _deployer,
        bytes32 _deploymentId
    ) external view returns (Deployment memory) {
        return _deployments[_deployer][_deploymentId];
    }

    /// @dev Checks the pool configuration to ensure that it is valid.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    function _checkPoolConfig(
        IHyperdrive.PoolDeployConfig memory _deployConfig
    ) internal view virtual {
        // Ensure that the minimum share reserves is at least 1e3. Deployer
        // coordinators should override this to be stricter.
        if (_deployConfig.minimumShareReserves < 1e3) {
            revert IHyperdriveDeployerCoordinator.InvalidMinimumShareReserves();
        }

        if (_deployConfig.checkpointDuration == 0) {
            revert IHyperdriveDeployerCoordinator.InvalidCheckpointDuration();
        }
        if (
            _deployConfig.positionDuration < _deployConfig.checkpointDuration ||
            _deployConfig.positionDuration % _deployConfig.checkpointDuration !=
            0
        ) {
            revert IHyperdriveDeployerCoordinator.InvalidPositionDuration();
        }

        // Ensure that the fees don't exceed 100%.
        if (
            _deployConfig.fees.curve > 1e18 ||
            _deployConfig.fees.flat > 1e18 ||
            _deployConfig.fees.governanceLP > 1e18 ||
            _deployConfig.fees.governanceZombie > 1e18
        ) {
            revert IHyperdriveDeployerCoordinator.InvalidFeeAmounts();
        }
    }

    /// @dev Gets the initial vault share price of the Hyperdrive pool.
    /// @param _extraData The extra data passed to the child deployers.
    /// @return The initial vault share price of the Hyperdrive pool.
    function _getInitialVaultSharePrice(
        bytes memory _extraData
    ) internal view virtual returns (uint256);

    /// @notice Copies the deploy config into a pool config.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    /// @return _config The pool configuration of the Hyperdrive pool.
    function _copyPoolConfig(
        IHyperdrive.PoolDeployConfig memory _deployConfig
    ) internal pure returns (IHyperdrive.PoolConfig memory _config) {
        // Copy the `PoolDeployConfig` into a `PoolConfig` struct.
        _config.baseToken = _deployConfig.baseToken;
        _config.linkerFactory = _deployConfig.linkerFactory;
        _config.linkerCodeHash = _deployConfig.linkerCodeHash;
        _config.minimumShareReserves = _deployConfig.minimumShareReserves;
        _config.minimumTransactionAmount = _deployConfig
            .minimumTransactionAmount;
        _config.positionDuration = _deployConfig.positionDuration;
        _config.checkpointDuration = _deployConfig.checkpointDuration;
        _config.timeStretch = _deployConfig.timeStretch;
        _config.governance = _deployConfig.governance;
        _config.feeCollector = _deployConfig.feeCollector;
        _config.fees = _deployConfig.fees;
    }
}
