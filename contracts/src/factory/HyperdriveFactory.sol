// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveFactory } from "../interfaces/IHyperdriveFactory.sol";
import { IHyperdriveDeployerCoordinator } from "../interfaces/IHyperdriveDeployerCoordinator.sol";
import { FixedPointMath, ONE } from "../libraries/FixedPointMath.sol";

/// @author DELV
/// @title HyperdriveFactory
/// @notice Deploys hyperdrive instances and initializes them. It also holds a
///         registry of all deployed hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveFactory is IHyperdriveFactory {
    using FixedPointMath for uint256;
    using SafeERC20 for ERC20;

    /// @notice The resolution for the checkpoint duration. Every checkpoint
    ///         duration must be a multiple of this resolution.
    uint256 public checkpointDurationResolution;

    /// @notice The governance address that updates the factory's configuration.
    address public governance;

    /// @notice The number of times the factory's deployer has been updated.
    uint256 public versionCounter = 1;

    /// @notice A mapping from deployed Hyperdrive instances to the version
    ///         of the deployer that deployed them.
    mapping(address instance => uint256 version) public isOfficial;

    /// @notice The governance address used when new instances are deployed.
    address public hyperdriveGovernance;

    /// @notice The linker factory used when new instances are deployed.
    address public linkerFactory;

    /// @notice The linker code hash used when new instances are deployed.
    bytes32 public linkerCodeHash;

    /// @notice The fee collector used when new instances are deployed.
    address public feeCollector;

    /// @notice The minimum checkpoint duration that can be used by new
    ///         deployments.
    uint256 public minCheckpointDuration;

    /// @notice The maximum checkpoint duration that can be used by new
    ///         deployments.
    uint256 public maxCheckpointDuration;

    /// @notice The minimum position duration that can be used by new
    ///         deployments.
    uint256 public minPositionDuration;

    /// @notice The maximum position duration that can be used by new
    ///         deployments.
    uint256 public maxPositionDuration;

    /// @notice The minimum fee parameters that can be used by new deployments.
    IHyperdrive.Fees internal _minFees;

    /// @notice The maximum fee parameters that can be used by new deployments.
    IHyperdrive.Fees internal _maxFees;

    /// @notice The defaultPausers used when new instances are deployed.
    address[] internal _defaultPausers;

    struct FactoryConfig {
        /// @dev The address which can update a factory.
        address governance;
        /// @dev The address which is set as the governor of hyperdrive.
        address hyperdriveGovernance;
        /// @dev The default addresses which will be set to have the pauser role.
        address[] defaultPausers;
        /// @dev The recipient of governance fees from new deployments.
        address feeCollector;
        /// @dev The resolution for the checkpoint duration.
        uint256 checkpointDurationResolution;
        /// @dev The minimum checkpoint duration that can be used in new
        ///      deployments.
        uint256 minCheckpointDuration;
        /// @dev The maximum checkpoint duration that can be used in new
        ///      deployments.
        uint256 maxCheckpointDuration;
        /// @dev The minimum position duration that can be used in new
        ///      deployments.
        uint256 minPositionDuration;
        /// @dev The maximum position duration that can be used in new
        ///      deployments.
        uint256 maxPositionDuration;
        /// @dev The lower bound on the fees that can be used in new deployments.
        IHyperdrive.Fees minFees;
        /// @dev The upper bound on the fees that can be used in new deployments.
        IHyperdrive.Fees maxFees;
        /// @dev The address of the linker factory.
        address linkerFactory;
        /// @dev The hash of the linker contract's constructor code.
        bytes32 linkerCodeHash;
    }

    /// @dev List of all deployer coordinators registered by governance.
    address[] internal _deployerCoordinators;

    /// @notice Mapping to check if a deployer coordinator has been registered
    ///         by governance.
    mapping(address => bool) public isDeployerCoordinator;

    /// @dev Array of all instances deployed by this factory.
    address[] internal _instances;

    /// @dev Mapping to check if an instance is in the _instances array.
    mapping(address => bool) public isInstance;

    /// @notice Initializes the factory.
    /// @param _factoryConfig Configuration of the Hyperdrive Factory.
    constructor(FactoryConfig memory _factoryConfig) {
        // Ensure that the minimum checkpoint duration is greater than or equal
        // to the checkpoint duration resolution and is a multiple of the
        // checkpoint duration resolution.
        if (
            _factoryConfig.minCheckpointDuration <
            _factoryConfig.checkpointDurationResolution ||
            _factoryConfig.minCheckpointDuration %
                _factoryConfig.checkpointDurationResolution !=
            0
        ) {
            revert IHyperdriveFactory.InvalidMinCheckpointDuration();
        }
        minCheckpointDuration = _factoryConfig.minCheckpointDuration;

        // Ensure that the maximum checkpoint duration is greater than or equal
        // to the minimum checkpoint duration and is a multiple of the
        // checkpoint duration resolution.
        if (
            _factoryConfig.maxCheckpointDuration <
            _factoryConfig.minCheckpointDuration ||
            _factoryConfig.maxCheckpointDuration %
                _factoryConfig.checkpointDurationResolution !=
            0
        ) {
            revert IHyperdriveFactory.InvalidMaxCheckpointDuration();
        }
        maxCheckpointDuration = _factoryConfig.maxCheckpointDuration;

        // Ensure that the minimum position duration is greater than or equal
        // to the maximum checkpoint duration and is a multiple of the
        // checkpoint duration resolution.
        if (
            _factoryConfig.minPositionDuration <
            _factoryConfig.maxCheckpointDuration ||
            _factoryConfig.minPositionDuration %
                _factoryConfig.checkpointDurationResolution !=
            0
        ) {
            revert IHyperdriveFactory.InvalidMinPositionDuration();
        }
        minPositionDuration = _factoryConfig.minPositionDuration;

        // Ensure that the maximum position duration is greater than or equal
        // to the minimum position duration and is a multiple of the checkpoint
        // duration resolution.
        if (
            _factoryConfig.maxPositionDuration <
            _factoryConfig.minPositionDuration ||
            _factoryConfig.maxPositionDuration %
                _factoryConfig.checkpointDurationResolution !=
            0
        ) {
            revert IHyperdriveFactory.InvalidMaxPositionDuration();
        }
        maxPositionDuration = _factoryConfig.maxPositionDuration;

        // Ensure that the max fees are each less than or equal to 100% and set
        // the fees.
        if (
            _factoryConfig.maxFees.curve > ONE ||
            _factoryConfig.maxFees.flat > ONE ||
            _factoryConfig.maxFees.governanceLP > ONE ||
            _factoryConfig.maxFees.governanceZombie > ONE
        ) {
            revert IHyperdriveFactory.InvalidMaxFees();
        }
        _maxFees = _factoryConfig.maxFees;

        // Ensure that the min fees are each less than or equal to the
        // corresponding and parameter in the max fees and set the fees.
        if (
            _factoryConfig.minFees.curve > _factoryConfig.maxFees.curve ||
            _factoryConfig.minFees.flat > _factoryConfig.maxFees.flat ||
            _factoryConfig.minFees.governanceLP >
            _factoryConfig.maxFees.governanceLP ||
            _factoryConfig.minFees.governanceZombie >
            _factoryConfig.maxFees.governanceZombie
        ) {
            revert IHyperdriveFactory.InvalidMinFees();
        }
        _minFees = _factoryConfig.minFees;

        // Initialize the other parameters.
        governance = _factoryConfig.governance;
        hyperdriveGovernance = _factoryConfig.hyperdriveGovernance;
        feeCollector = _factoryConfig.feeCollector;
        _defaultPausers = _factoryConfig.defaultPausers;
        linkerFactory = _factoryConfig.linkerFactory;
        linkerCodeHash = _factoryConfig.linkerCodeHash;
        checkpointDurationResolution = _factoryConfig
            .checkpointDurationResolution;
    }

    /// @dev Ensure that the sender is the governance address.
    modifier onlyGovernance() {
        if (msg.sender != governance) {
            revert IHyperdriveFactory.Unauthorized();
        }
        _;
    }

    /// @notice Allows governance to transfer the governance role.
    /// @param _governance The new governance address.
    function updateGovernance(address _governance) external onlyGovernance {
        governance = _governance;
        emit GovernanceUpdated(_governance);
    }

    /// @notice Allows governance to change the hyperdrive governance address
    /// @param _hyperdriveGovernance The new hyperdrive governance address.
    function updateHyperdriveGovernance(
        address _hyperdriveGovernance
    ) external onlyGovernance {
        hyperdriveGovernance = _hyperdriveGovernance;
        emit HyperdriveGovernanceUpdated(_hyperdriveGovernance);
    }

    /// @notice Allows governance to change the linker factory.
    /// @param _linkerFactory The new linker factory.
    function updateLinkerFactory(
        address _linkerFactory
    ) external onlyGovernance {
        linkerFactory = _linkerFactory;
        emit LinkerFactoryUpdated(_linkerFactory);
    }

    /// @notice Allows governance to change the linker code hash. This allows
    ///         governance to update the implementation of the ERC20Forwarder.
    /// @param _linkerCodeHash The new linker code hash.
    function updateLinkerCodeHash(
        bytes32 _linkerCodeHash
    ) external onlyGovernance {
        linkerCodeHash = _linkerCodeHash;
        emit LinkerCodeHashUpdated(_linkerCodeHash);
    }

    /// @notice Allows governance to change the fee collector address.
    /// @param _feeCollector The new fee collector address.
    function updateFeeCollector(address _feeCollector) external onlyGovernance {
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(_feeCollector);
    }

    /// @notice Allows governance to change the checkpoint duration resolution.
    /// @param _checkpointDurationResolution The new checkpoint duration
    ///        resolution.
    function updateCheckpointDurationResolution(
        uint256 _checkpointDurationResolution
    ) external onlyGovernance {
        // Ensure that the minimum checkpoint duration, maximum checkpoint
        // duration, minimum position duration, and maximum position duration
        // are all multiples of the checkpoint duration resolution.
        if (
            minCheckpointDuration % _checkpointDurationResolution != 0 ||
            maxCheckpointDuration % _checkpointDurationResolution != 0 ||
            minPositionDuration % _checkpointDurationResolution != 0 ||
            maxPositionDuration % _checkpointDurationResolution != 0
        ) {
            revert IHyperdriveFactory.InvalidCheckpointDurationResolution();
        }

        // Update the checkpoint duration resolution and emit an event.
        checkpointDurationResolution = _checkpointDurationResolution;
        emit CheckpointDurationResolutionUpdated(_checkpointDurationResolution);
    }

    /// @notice Allows governance to update the maximum checkpoint duration.
    /// @param _maxCheckpointDuration The new maximum checkpoint duration.
    function updateMaxCheckpointDuration(
        uint256 _maxCheckpointDuration
    ) external onlyGovernance {
        // Ensure that the maximum checkpoint duration is greater than or equal
        // to the minimum checkpoint duration and is a multiple of the
        // checkpoint duration resolution. Also ensure that the maximum
        // checkpoint duration is less than or equal to the minimum position
        // duration.
        if (
            _maxCheckpointDuration < minCheckpointDuration ||
            _maxCheckpointDuration % checkpointDurationResolution != 0 ||
            _maxCheckpointDuration > minPositionDuration
        ) {
            revert IHyperdriveFactory.InvalidMaxCheckpointDuration();
        }

        // Update the maximum checkpoint duration and emit an event.
        maxCheckpointDuration = _maxCheckpointDuration;
        emit MaxCheckpointDurationUpdated(_maxCheckpointDuration);
    }

    /// @notice Allows governance to update the minimum checkpoint duration.
    /// @param _minCheckpointDuration The new minimum checkpoint duration.
    function updateMinCheckpointDuration(
        uint256 _minCheckpointDuration
    ) external onlyGovernance {
        // Ensure that the minimum checkpoint duration is greater than or equal
        // to the checkpoint duration resolution and is a multiple of the
        // checkpoint duration resolution. Also ensure that the minimum
        // checkpoint duration is less than or equal to the maximum checkpoint
        // duration.
        if (
            _minCheckpointDuration < checkpointDurationResolution ||
            _minCheckpointDuration % checkpointDurationResolution != 0 ||
            _minCheckpointDuration > maxCheckpointDuration
        ) {
            revert IHyperdriveFactory.InvalidMinCheckpointDuration();
        }

        // Update the minimum checkpoint duration and emit an event.
        minCheckpointDuration = _minCheckpointDuration;
        emit MinCheckpointDurationUpdated(_minCheckpointDuration);
    }

    /// @notice Allows governance to update the maximum position duration.
    /// @param _maxPositionDuration The new maximum position duration.
    function updateMaxPositionDuration(
        uint256 _maxPositionDuration
    ) external onlyGovernance {
        // Ensure that the maximum position duration is greater than or equal
        // to the minimum position duration and is a multiple of the checkpoint
        // duration resolution.
        if (
            _maxPositionDuration < minPositionDuration ||
            _maxPositionDuration % checkpointDurationResolution != 0
        ) {
            revert IHyperdriveFactory.InvalidMaxPositionDuration();
        }

        // Update the maximum position duration and emit an event.
        maxPositionDuration = _maxPositionDuration;
        emit MaxPositionDurationUpdated(_maxPositionDuration);
    }

    /// @notice Allows governance to update the minimum position duration.
    /// @param _minPositionDuration The new minimum position duration.
    function updateMinPositionDuration(
        uint256 _minPositionDuration
    ) external onlyGovernance {
        // Ensure that the minimum position duration is greater than or equal
        // to the maximum checkpoint duration and is a multiple of the
        // checkpoint duration resolution. Also ensure that the minimum position
        // duration is less than or equal to the maximum position duration.
        if (
            _minPositionDuration < maxCheckpointDuration ||
            _minPositionDuration % checkpointDurationResolution != 0 ||
            _minPositionDuration > maxPositionDuration
        ) {
            revert IHyperdriveFactory.InvalidMinPositionDuration();
        }

        // Update the minimum position duration and emit an event.
        minPositionDuration = _minPositionDuration;
        emit MinPositionDurationUpdated(_minPositionDuration);
    }

    /// @notice Allows governance to update the maximum fee parameters.
    /// @param __maxFees The new maximum fee parameters.
    function updateMaxFees(
        IHyperdrive.Fees calldata __maxFees
    ) external onlyGovernance {
        // Ensure that the max fees are each less than or equal to 100% and that
        // the max fees are each greater than or equal to the corresponding min
        // fee.
        if (
            __maxFees.curve > ONE ||
            __maxFees.flat > ONE ||
            __maxFees.governanceLP > ONE ||
            __maxFees.governanceZombie > ONE ||
            __maxFees.curve < _minFees.curve ||
            __maxFees.flat < _minFees.flat ||
            __maxFees.governanceLP < _minFees.governanceLP ||
            __maxFees.governanceZombie < _minFees.governanceZombie
        ) {
            revert IHyperdriveFactory.InvalidMaxFees();
        }

        // Update the max fees and emit an event.
        _maxFees = __maxFees;
        emit MaxFeesUpdated(__maxFees);
    }

    /// @notice Allows governance to update the minimum fee parameters.
    /// @param __minFees The new minimum fee parameters.
    function updateMinFees(
        IHyperdrive.Fees calldata __minFees
    ) external onlyGovernance {
        // Ensure that the min fees are each less than or the corresponding max
        // fee.
        if (
            __minFees.curve > _maxFees.curve ||
            __minFees.flat > _maxFees.flat ||
            __minFees.governanceLP > _maxFees.governanceLP ||
            __minFees.governanceZombie > _maxFees.governanceZombie
        ) {
            revert IHyperdriveFactory.InvalidMinFees();
        }

        // Update the max fees and emit an event.
        _minFees = __minFees;
        emit MinFeesUpdated(__minFees);
    }

    /// @notice Allows governance to change the default pausers.
    /// @param _defaultPausers_ The new list of default pausers.
    function updateDefaultPausers(
        address[] calldata _defaultPausers_
    ) external onlyGovernance {
        _defaultPausers = _defaultPausers_;
        emit DefaultPausersUpdated(_defaultPausers_);
    }

    /// @notice Allows governance to add a new deployer coordinator.
    /// @param _deployerCoordinator The new deployer coordinator.
    function addDeployerCoordinator(
        address _deployerCoordinator
    ) external onlyGovernance {
        if (isDeployerCoordinator[_deployerCoordinator]) {
            revert IHyperdriveFactory.DeployerCoordinatorAlreadyAdded();
        }
        isDeployerCoordinator[_deployerCoordinator] = true;
        _deployerCoordinators.push(_deployerCoordinator);
        emit DeployerCoordinatorAdded(_deployerCoordinator);
    }

    /// @notice Allows governance to remove an existing deployer coordinator.
    /// @param _deployerCoordinator The deployer coordinator to remove.
    /// @param _index The index of the deployer coordinator to remove.
    function removeDeployerCoordinator(
        address _deployerCoordinator,
        uint256 _index
    ) external onlyGovernance {
        if (!isDeployerCoordinator[_deployerCoordinator]) {
            revert IHyperdriveFactory.DeployerCoordinatorNotAdded();
        }
        if (_deployerCoordinators[_index] != _deployerCoordinator) {
            revert IHyperdriveFactory.DeployerCoordinatorIndexMismatch();
        }
        isDeployerCoordinator[_deployerCoordinator] = false;
        _deployerCoordinators[_index] = _deployerCoordinators[
            _deployerCoordinators.length - 1
        ];
        _deployerCoordinators.pop();
        emit DeployerCoordinatorRemoved(_deployerCoordinator);
    }

    /// @notice Deploys a Hyperdrive instance with the factory's configuration.
    /// @dev This function is declared as payable to allow payable overrides
    ///      to accept ether on initialization, but payability is not supported
    ///      by default.
    /// @param _deploymentId The deployment ID to use when deploying the pool.
    /// @param _deployerCoordinator The deployer coordinator to use in this
    ///        deployment.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains data necessary for the
    ///        specific deployer.
    /// @param _contribution Base token to call init with
    /// @param _apr The apr to call init with
    /// @param _initializeExtraData The extra data for the `initialize` call.
    /// @param _salt The create2 salt to use for the deployment.
    /// @return The hyperdrive address deployed.
    function deployAndInitialize(
        bytes32 _deploymentId,
        address _deployerCoordinator,
        IHyperdrive.PoolDeployConfig memory _config,
        bytes memory _extraData,
        uint256 _contribution,
        uint256 _apr,
        bytes memory _initializeExtraData,
        bytes32 _salt
    ) external payable returns (IHyperdrive) {
        // Ensure that the deployer coordinator has been registered.
        if (!isDeployerCoordinator[_deployerCoordinator]) {
            revert IHyperdriveFactory.InvalidDeployerCoordinator();
        }

        // Override the config values to the default values set by governance
        // and ensure that the config is valid.
        _overrideConfig(_config);

        // Deploy the Hyperdrive instance with the specified deployer
        // coordinator.
        IHyperdrive hyperdrive = IHyperdrive(
            IHyperdriveDeployerCoordinator(_deployerCoordinator).deploy(
                // NOTE: We hash the deployer's address into the deployment ID
                // to prevent their deployment from being front-run.
                keccak256(abi.encode(msg.sender, _deploymentId)),
                _config,
                _extraData,
                _salt
            )
        );

        // Add this instance to the registry and emit an event with the
        // deployment configuration.
        isOfficial[address(hyperdrive)] = versionCounter;
        _config.governance = hyperdriveGovernance;
        emit Deployed(versionCounter, address(hyperdrive), _config, _extraData);

        // Add the newly deployed Hyperdrive instance to the registry.
        _instances.push(address(hyperdrive));
        isInstance[address(hyperdrive)] = true;

        // Initialize the Hyperdrive instance.
        uint256 refund;
        if (msg.value >= _contribution) {
            // Only the contribution amount of ether will be passed to
            // Hyperdrive.
            refund = msg.value - _contribution;

            // Initialize the Hyperdrive instance.
            hyperdrive.initialize{ value: _contribution }(
                _contribution,
                _apr,
                IHyperdrive.Options({
                    destination: msg.sender,
                    asBase: true,
                    extraData: _initializeExtraData
                })
            );
        } else {
            // None of the provided ether is used for the contribution.
            refund = msg.value;

            // Transfer the contribution to this contract and set an approval
            // on Hyperdrive to prepare for initialization.
            ERC20(address(_config.baseToken)).safeTransferFrom(
                msg.sender,
                address(this),
                _contribution
            );
            ERC20(address(_config.baseToken)).forceApprove(
                address(hyperdrive),
                _contribution
            );

            // Initialize the Hyperdrive instance.
            hyperdrive.initialize(
                _contribution,
                _apr,
                IHyperdrive.Options({
                    destination: msg.sender,
                    asBase: true,
                    extraData: _initializeExtraData
                })
            );
        }

        // Refund any excess ether that was sent to this contract.
        if (refund > 0) {
            (bool success, ) = payable(msg.sender).call{ value: refund }("");
            if (!success) {
                revert IHyperdriveFactory.TransferFailed();
            }
        }

        // Set the default pausers and transfer the governance status to the
        // hyperdrive governance address.
        for (uint256 i = 0; i < _defaultPausers.length; ) {
            hyperdrive.setPauser(_defaultPausers[i], true);
            unchecked {
                ++i;
            }
        }
        hyperdrive.setGovernance(hyperdriveGovernance);

        return hyperdrive;
    }

    /// @notice Deploys a Hyperdrive target with the factory's configuration.
    /// @param _deploymentId The deployment ID to use when deploying the pool.
    /// @param _deployerCoordinator The deployer coordinator to use in this
    ///        deployment.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains data necessary for the
    ///        specific deployer.
    /// @param _targetIndex The index of the target to deploy.
    /// @param _salt The create2 salt to use for the deployment.
    /// @return The target address deployed.
    function deployTarget(
        bytes32 _deploymentId,
        address _deployerCoordinator,
        IHyperdrive.PoolDeployConfig memory _config,
        bytes memory _extraData,
        uint256 _targetIndex,
        bytes32 _salt
    ) external returns (address) {
        // Ensure that the deployer coordinator has been registered.
        if (!isDeployerCoordinator[_deployerCoordinator]) {
            revert IHyperdriveFactory.InvalidDeployerCoordinator();
        }

        // Override the config values to the default values set by governance
        // and ensure that the config is valid.
        _overrideConfig(_config);

        // Deploy the target instance with the specified deployer coordinator.
        address target = IHyperdriveDeployerCoordinator(_deployerCoordinator)
            .deployTarget(
                // NOTE: We hash the deployer's address into the deployment ID
                // to prevent their deployment from being front-run.
                keccak256(abi.encode(msg.sender, _deploymentId)),
                _config,
                _extraData,
                _targetIndex,
                _salt
            );

        return target;
    }

    /// @notice Gets the max fees.
    /// @return The max fees.
    function maxFees() external view returns (IHyperdrive.Fees memory) {
        return _maxFees;
    }

    /// @notice Gets the min fees.
    /// @return The min fees.
    function minFees() external view returns (IHyperdrive.Fees memory) {
        return _minFees;
    }

    /// @notice Gets the default pausers.
    /// @return The default pausers.
    function defaultPausers() external view returns (address[] memory) {
        return _defaultPausers;
    }

    /// @notice Gets the number of instances deployed by this factory.
    /// @return The number of instances deployed by this factory.
    function getNumberOfInstances() external view returns (uint256) {
        return _instances.length;
    }

    /// @notice Gets the instance at the specified index.
    /// @param index The index of the instance to get.
    /// @return The instance at the specified index.
    function getInstanceAtIndex(uint256 index) external view returns (address) {
        return _instances[index];
    }

    /// @notice Returns the _instances array according to specified indices.
    /// @param startIndex The starting index of the instances to get.
    /// @param endIndex The ending index of the instances to get.
    /// @return range The resulting custom portion of the _instances array.
    function getInstancesInRange(
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (address[] memory range) {
        // If the indexes are malformed, revert.
        if (startIndex > endIndex) {
            revert IHyperdriveFactory.InvalidIndexes();
        }
        if (endIndex > _instances.length) {
            revert IHyperdriveFactory.EndIndexTooLarge();
        }

        // Return the range of instances.
        range = new address[](endIndex - startIndex + 1);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            range[i - startIndex] = _instances[i];
        }
    }

    /// @notice Gets the number of deployer coordinators registered in this
    ///         factory.
    /// @return The number of deployer coordinators deployed by this factory.
    function getNumberOfDeployerCoordinators() external view returns (uint256) {
        return _deployerCoordinators.length;
    }

    /// @notice Gets the deployer coordinator at the specified index.
    /// @param index The index of the deployer coordinator to get.
    /// @return The deployer coordinator at the specified index.
    function getDeployerCoordinatorAtIndex(
        uint256 index
    ) external view returns (address) {
        return _deployerCoordinators[index];
    }

    /// @notice Returns the deployer coordinators with an index between the
    ///         starting and ending indexes (inclusive).
    /// @param startIndex The starting index (inclusive).
    /// @param endIndex The ending index (inclusive).
    /// @return range The deployer coordinators within the specified range.
    function getDeployerCoordinatorsInRange(
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (address[] memory range) {
        // If the indexes are malformed, revert.
        if (startIndex > endIndex) {
            revert IHyperdriveFactory.InvalidIndexes();
        }
        if (endIndex > _deployerCoordinators.length) {
            revert IHyperdriveFactory.EndIndexTooLarge();
        }

        // Return the range of instances.
        range = new address[](endIndex - startIndex + 1);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            range[i - startIndex] = _deployerCoordinators[i];
        }
    }

    /// @dev Overrides the config values to the default values set by
    ///      governance. In the process of overriding these parameters, this
    ///      verifies that the specified config is valid.
    /// @param _config The config to override.
    function _overrideConfig(
        IHyperdrive.PoolDeployConfig memory _config
    ) internal view {
        // Ensure that the specified checkpoint duration is within the minimum
        // and maximum checkpoint durations and is a multiple of the checkpoint
        // duration resolution.
        if (
            _config.checkpointDuration < minCheckpointDuration ||
            _config.checkpointDuration > maxCheckpointDuration ||
            _config.checkpointDuration % checkpointDurationResolution != 0
        ) {
            revert IHyperdriveFactory.InvalidCheckpointDuration();
        }

        // Ensure that the specified checkpoint duration is within the minimum
        // and maximum position durations and is a multiple of the specified
        // checkpoint duration.
        if (
            _config.positionDuration < minPositionDuration ||
            _config.positionDuration > maxPositionDuration ||
            _config.positionDuration % _config.checkpointDuration != 0
        ) {
            revert IHyperdriveFactory.InvalidPositionDuration();
        }

        // Ensure that the specified fees are within the minimum and maximum fees.
        if (
            _config.fees.curve > _maxFees.curve ||
            _config.fees.flat > _maxFees.flat ||
            _config.fees.governanceLP > _maxFees.governanceLP ||
            _config.fees.governanceZombie > _maxFees.governanceZombie ||
            _config.fees.curve < _minFees.curve ||
            _config.fees.flat < _minFees.flat ||
            _config.fees.governanceLP < _minFees.governanceLP ||
            _config.fees.governanceZombie < _minFees.governanceZombie
        ) {
            revert IHyperdriveFactory.InvalidFees();
        }

        // Ensure that the linker factory, linker code hash, fee collector,
        // and governance addresses aren't set. This ensures that the
        // deployer isn't trying to set these values.
        if (
            _config.linkerFactory != address(0) ||
            _config.linkerCodeHash != bytes32(0) ||
            _config.feeCollector != address(0) ||
            _config.governance != address(0)
        ) {
            revert IHyperdriveFactory.InvalidDeployConfig();
        }

        // Override the config values to the default values set by governance.
        // The factory assumes the governance role during deployment so that it
        // can set up some initial values; however the governance role will
        // ultimately be transferred to the hyperdrive governance address.
        _config.linkerFactory = linkerFactory;
        _config.linkerCodeHash = linkerCodeHash;
        _config.feeCollector = feeCollector;
        _config.governance = address(this);
    }
}
