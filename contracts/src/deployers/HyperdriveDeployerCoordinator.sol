// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveCoreDeployer } from "../interfaces/IHyperdriveCoreDeployer.sol";
import { IHyperdriveDeployerCoordinator } from "../interfaces/IHyperdriveDeployerCoordinator.sol";
import { IHyperdriveTargetDeployer } from "../interfaces/IHyperdriveTargetDeployer.sol";
import { VERSION, NUM_TARGETS } from "../libraries/Constants.sol";
import { ONE } from "../libraries/FixedPointMath.sol";

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

    /// @notice The factory that this deployer will be registered with.
    address public immutable factory;

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

    /// @notice The deployer coordinator's name.
    string public override name;

    /// @notice A mapping from deployment ID to deployment.
    mapping(bytes32 => Deployment) internal _deployments;

    /// @notice Instantiates the deployer coordinator.
    /// @param _name The deployer coordinator's name.
    /// @param _factory The factory that this deployer will be registered with.
    /// @param _coreDeployer The core deployer.
    /// @param _target0Deployer The target0 deployer.
    /// @param _target1Deployer The target1 deployer.
    /// @param _target2Deployer The target2 deployer.
    /// @param _target3Deployer The target3 deployer.
    /// @param _target4Deployer The target4 deployer.
    constructor(
        string memory _name,
        address _factory,
        address _coreDeployer,
        address _target0Deployer,
        address _target1Deployer,
        address _target2Deployer,
        address _target3Deployer,
        address _target4Deployer
    ) {
        name = _name;
        factory = _factory;
        coreDeployer = _coreDeployer;
        target0Deployer = _target0Deployer;
        target1Deployer = _target1Deployer;
        target2Deployer = _target2Deployer;
        target3Deployer = _target3Deployer;
        target4Deployer = _target4Deployer;
    }

    /// @dev Ensures that the contract is being called by the associated
    ///      factory.
    modifier onlyFactory() {
        if (msg.sender != factory) {
            revert IHyperdriveDeployerCoordinator.SenderIsNotFactory();
        }
        _;
    }

    /// @notice Gets the deployer coordinator's kind.
    /// @notice The deployer coordinator's kind.
    function kind() external pure virtual returns (string memory);

    /// @notice Returns the deployer coordinator's version.
    /// @notice The deployer coordinator's version.
    function version() external pure returns (string memory) {
        return VERSION;
    }

    /// @notice Deploys a Hyperdrive instance with the given parameters.
    /// @dev This can only be deployed by the associated factory.
    /// @param _deploymentId The ID of the deployment.
    /// @param __name The name of the Hyperdrive pool.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains the pool and sweep targets.
    /// @param _salt The create2 salt used to deploy Hyperdrive.
    /// @return The address of the newly deployed Hyperdrive instance.
    function deployHyperdrive(
        bytes32 _deploymentId,
        string memory __name,
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory _extraData,
        bytes32 _salt
    ) external onlyFactory returns (address) {
        // Ensure that the Hyperdrive entrypoint has not already been deployed.
        Deployment memory deployment = _deployments[_deploymentId];
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
        _checkPoolConfig(_deployConfig, _extraData);

        // Convert the deploy config into the pool config and set the initial
        // vault share price.
        IHyperdrive.PoolConfig memory config = _copyPoolConfig(_deployConfig);
        config.initialVaultSharePrice = deployment.initialSharePrice;

        // Deploy the Hyperdrive instance and add it to the deployment struct.
        bytes32 deploymentId = _deploymentId; // Avoid stack too deep error
        bytes32 salt = _salt; // Avoid stack too deep error
        address hyperdrive = IHyperdriveCoreDeployer(coreDeployer)
            .deployHyperdrive(
                __name,
                config,
                IHyperdriveAdminController(factory),
                _extraData,
                deployment.target0,
                deployment.target1,
                deployment.target2,
                deployment.target3,
                deployment.target4,
                // NOTE: We hash the deployment ID with the salt to prevent the
                // front-running of deployments.
                keccak256(abi.encode(deploymentId, salt))
            );
        _deployments[_deploymentId].hyperdrive = hyperdrive;

        return hyperdrive;
    }

    /// @notice Deploys a Hyperdrive target instance with the given parameters.
    /// @dev This can only be deployed by the associated factory.
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
    ) external onlyFactory returns (address target) {
        // If the target index is 0, then we're deploying the target0 instance.
        // By convention, this target must be deployed first, and as part of the
        // deployment of target0, we will register the deployment in the state.
        Deployment storage deployment = _deployments[_deploymentId];
        if (_targetIndex == 0) {
            // Ensure that the deployment is a fresh deployment. We can check
            // this by ensuring that the config hash is not set.
            if (deployment.configHash != bytes32(0)) {
                revert IHyperdriveDeployerCoordinator.DeploymentAlreadyExists();
            }

            // Check the pool configuration to ensure that it's a valid
            // configuration for this instance.
            _checkPoolConfig(_deployConfig, _extraData);

            // Get the initial share price and the hashes of the config and extra
            // data.
            uint256 initialSharePrice = _getInitialVaultSharePrice(
                _deployConfig,
                _extraData
            );
            bytes32 configHash_ = keccak256(abi.encode(_deployConfig));
            bytes32 extraDataHash = keccak256(_extraData);

            // Convert the deploy config into the pool config and set the initial
            // vault share price.
            IHyperdrive.PoolConfig memory config_ = _copyPoolConfig(
                _deployConfig
            );
            config_.initialVaultSharePrice = initialSharePrice;

            // Deploy the target0 contract.
            target = IHyperdriveTargetDeployer(target0Deployer).deployTarget(
                config_,
                IHyperdriveAdminController(factory),
                _extraData,
                // NOTE: We hash the deployment ID with the salt to prevent the
                // front-running of deployments.
                keccak256(abi.encode(_deploymentId, _salt))
            );

            // Store the deployment.
            deployment.configHash = configHash_;
            deployment.extraDataHash = extraDataHash;
            deployment.initialSharePrice = initialSharePrice;
            deployment.target0 = target;

            return target;
        }

        // Ensure that the deployment is not a fresh deployment. We can check
        // this by ensuring that the config hash is set.
        bytes32 configHash = _deployments[_deploymentId].configHash;
        if (configHash == bytes32(0)) {
            revert IHyperdriveDeployerCoordinator.DeploymentDoesNotExist();
        }

        // Ensure that the provided config matches the config hash.
        if (keccak256(abi.encode(_deployConfig)) != configHash) {
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
        _checkPoolConfig(_deployConfig, _extraData);

        // Convert the deploy config into the pool config and set the initial
        // vault share price.
        IHyperdrive.PoolConfig memory config = _copyPoolConfig(_deployConfig);
        config.initialVaultSharePrice = deployment.initialSharePrice;

        // If the target index is greater than 0, then we're deploying one of
        // the other target instances. We don't allow targets to be deployed
        // more than once, and their addresses are stored in the deployment
        // state.
        if (_targetIndex == 1) {
            if (deployment.target1 != address(0)) {
                revert IHyperdriveDeployerCoordinator.TargetAlreadyDeployed();
            }
            target = IHyperdriveTargetDeployer(target1Deployer).deployTarget(
                config,
                IHyperdriveAdminController(factory),
                _extraData,
                keccak256(abi.encode(msg.sender, _deploymentId, _salt))
            );
            deployment.target1 = target;
        } else if (_targetIndex == 2) {
            if (deployment.target2 != address(0)) {
                revert IHyperdriveDeployerCoordinator.TargetAlreadyDeployed();
            }
            target = IHyperdriveTargetDeployer(target2Deployer).deployTarget(
                config,
                IHyperdriveAdminController(factory),
                _extraData,
                keccak256(abi.encode(msg.sender, _deploymentId, _salt))
            );
            deployment.target2 = target;
        } else if (_targetIndex == 3) {
            if (deployment.target3 != address(0)) {
                revert IHyperdriveDeployerCoordinator.TargetAlreadyDeployed();
            }
            target = IHyperdriveTargetDeployer(target3Deployer).deployTarget(
                config,
                IHyperdriveAdminController(factory),
                _extraData,
                keccak256(abi.encode(msg.sender, _deploymentId, _salt))
            );
            deployment.target3 = target;
        } else if (_targetIndex == 4) {
            if (deployment.target4 != address(0)) {
                revert IHyperdriveDeployerCoordinator.TargetAlreadyDeployed();
            }
            target = IHyperdriveTargetDeployer(target4Deployer).deployTarget(
                config,
                IHyperdriveAdminController(factory),
                _extraData,
                keccak256(abi.encode(msg.sender, _deploymentId, _salt))
            );
            deployment.target4 = target;
        } else {
            revert IHyperdriveDeployerCoordinator.InvalidTargetIndex();
        }

        return target;
    }

    /// @notice Initializes a pool that was deployed by this coordinator.
    /// @dev This can only be deployed by the associated factory.
    /// @dev This function utilizes several helper functions that provide
    ///      flexibility to implementations.
    /// @param _deploymentId The ID of the deployment.
    /// @param _lp The LP that is initializing the pool.
    /// @param _contribution The amount of capital to supply. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _apr The target APR.
    /// @param _options The options that configure how the initialization is
    ///        settled.
    /// @return lpShares The initial number of LP shares created.
    function initialize(
        bytes32 _deploymentId,
        address _lp,
        uint256 _contribution,
        uint256 _apr,
        IHyperdrive.Options memory _options
    ) external payable onlyFactory returns (uint256 lpShares) {
        // Check that the message value is valid.
        _checkMessageValue();

        // Ensure that the instance has been fully deployed.
        IHyperdrive hyperdrive = IHyperdrive(
            _deployments[_deploymentId].hyperdrive
        );
        if (address(hyperdrive) == address(0)) {
            revert IHyperdriveDeployerCoordinator.HyperdriveIsNotDeployed();
        }

        // Prepare for initialization by drawing funds from the user.
        uint256 value = _prepareInitialize(
            hyperdrive,
            _lp,
            _contribution,
            _options
        );

        // Initialize the deployment.
        lpShares = hyperdrive.initialize{ value: value }(
            _contribution,
            _apr,
            _options
        );

        // Refund any excess ether that was sent.
        uint256 refund = msg.value - value;
        if (refund > 0) {
            (bool success, ) = payable(msg.sender).call{ value: refund }("");
            if (!success) {
                revert IHyperdriveDeployerCoordinator.TransferFailed();
            }
        }

        return lpShares;
    }

    /// @notice Gets the deployment specified by the deployment ID.
    /// @param _deploymentId The deployment ID.
    /// @return The deployment.
    function deployments(
        bytes32 _deploymentId
    ) external view returns (Deployment memory) {
        return _deployments[_deploymentId];
    }

    /// @notice Gets the number of targets that need to be deployed for a full
    ///         deployment.
    /// @return numTargets The number of targets that need to be deployed for a
    ///         full deployment.
    function getNumberOfTargets() external pure returns (uint256) {
        return NUM_TARGETS;
    }

    /// @dev Prepares the coordinator for initialization by drawing funds from
    ///      the LP, if necessary.
    /// @param _hyperdrive The Hyperdrive instance that is being initialized.
    /// @param _lp The LP that is initializing the pool.
    /// @param _contribution The amount of capital to supply. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _options The options that configure how the initialization is
    ///        settled.
    /// @return value The value that should be sent in the initialize
    ///         transaction.
    function _prepareInitialize(
        IHyperdrive _hyperdrive,
        address _lp,
        uint256 _contribution,
        IHyperdrive.Options memory _options
    ) internal virtual returns (uint256 value);

    /// @dev A yield source dependent check that prevents ether from being
    ///      transferred to Hyperdrive instances that don't accept ether.
    function _checkMessageValue() internal view virtual;

    /// @dev Checks the pool configuration to ensure that it is valid.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    function _checkPoolConfig(
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory // unused _extraData
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
            _deployConfig.fees.curve > ONE ||
            _deployConfig.fees.flat > ONE ||
            _deployConfig.fees.governanceLP > ONE ||
            _deployConfig.fees.governanceZombie > ONE
        ) {
            revert IHyperdriveDeployerCoordinator.InvalidFeeAmounts();
        }
    }

    /// @dev Gets the initial vault share price of the Hyperdrive pool.
    /// @param _deployConfig The deploy config that will be used to deploy the
    ///        pool.
    /// @param _extraData The extra data passed to the child deployers.
    /// @return The initial vault share price of the Hyperdrive pool.
    function _getInitialVaultSharePrice(
        IHyperdrive.PoolDeployConfig memory _deployConfig,
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
        _config.vaultSharesToken = _deployConfig.vaultSharesToken;
        _config.linkerFactory = _deployConfig.linkerFactory;
        _config.linkerCodeHash = _deployConfig.linkerCodeHash;
        _config.minimumShareReserves = _deployConfig.minimumShareReserves;
        _config.minimumTransactionAmount = _deployConfig
            .minimumTransactionAmount;
        _config.circuitBreakerDelta = _deployConfig.circuitBreakerDelta;
        _config.positionDuration = _deployConfig.positionDuration;
        _config.checkpointDuration = _deployConfig.checkpointDuration;
        _config.timeStretch = _deployConfig.timeStretch;
        _config.governance = _deployConfig.governance;
        _config.feeCollector = _deployConfig.feeCollector;
        _config.sweepCollector = _deployConfig.sweepCollector;
        _config.checkpointRewarder = _deployConfig.checkpointRewarder;
        _config.fees = _deployConfig.fees;
    }
}
