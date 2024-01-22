// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IDeployerCoordinator } from "../interfaces/IDeployerCoordinator.sol";
import { FixedPointMath, ONE } from "../libraries/FixedPointMath.sol";

/// @author DELV
/// @title HyperdriveFactory
/// @notice Deploys hyperdrive instances and initializes them. It also holds a
///         registry of all deployed hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveFactory {
    using FixedPointMath for uint256;
    using SafeTransferLib for ERC20;

    /// @notice Emitted when new instances are deployed.
    event Deployed(
        uint256 indexed version,
        address hyperdrive,
        IHyperdrive.PoolDeployConfig config,
        bytes extraData
    );

    /// @notice Emitted when a new deployer coordinator is added.
    event DeployerCoordinatorAdded(address deployerCoordinator);

    /// @notice Emitted when a deployer coordinator is removed.
    event DeployerCoordinatorRemoved(address deployerCoordinator);

    /// @notice Emitted when the default pausers are updated.
    event DefaultPausersUpdated(address[] newDefaultPausers);

    /// @notice Emitted when the fee collector is updated.
    event FeeCollectorUpdated(address newFeeCollector);

    /// @notice Emitted when governance is transferred.
    event GovernanceUpdated(address governance);

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

    /// @notice Mapping to check if a deployer coordinator has been registered'
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
            revert IHyperdrive.InvalidMinCheckpointDuration();
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
            revert IHyperdrive.InvalidMaxCheckpointDuration();
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
            revert IHyperdrive.InvalidMinPositionDuration();
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
            revert IHyperdrive.InvalidMaxPositionDuration();
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
            revert IHyperdrive.InvalidMaxFees();
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
            revert IHyperdrive.InvalidMinFees();
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
        if (msg.sender != governance) revert IHyperdrive.Unauthorized();
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
            revert IHyperdrive.InvalidCheckpointDurationResolution();
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
            revert IHyperdrive.InvalidMaxCheckpointDuration();
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
            revert IHyperdrive.InvalidMinCheckpointDuration();
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
            revert IHyperdrive.InvalidMaxPositionDuration();
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
            revert IHyperdrive.InvalidMinPositionDuration();
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
            revert IHyperdrive.InvalidMaxFees();
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
            revert IHyperdrive.InvalidMinFees();
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
            revert IHyperdrive.DeployerCoordinatorAlreadyAdded();
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
            revert IHyperdrive.DeployerCoordinatorNotAdded();
        }
        if (_deployerCoordinators[_index] != _deployerCoordinator) {
            revert IHyperdrive.DeployerCoordinatorIndexMismatch();
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
    /// @param _deployerCoordinator The deployer coordinator to use in this
    ///        deployment.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains data necessary for the
    ///        specific deployer.
    /// @param _contribution Base token to call init with
    /// @param _apr The apr to call init with
    /// @param _initializeExtraData The extra data for the `initialize` call.
    /// @return The hyperdrive address deployed.
    function deployAndInitialize(
        address _deployerCoordinator,
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory _extraData,
        uint256 _contribution,
        uint256 _apr,
        bytes memory _initializeExtraData
    ) public payable virtual returns (IHyperdrive) {
        // Ensure that the target deployer has been registered.
        if (!isDeployerCoordinator[_deployerCoordinator]) {
            revert IHyperdrive.InvalidDeployerCoordinator();
        }

        // Ensure that the specified checkpoint duration is within the minimum
        // and maximum checkpoint durations and is a multiple of the checkpoint
        // duration resolution.
        if (
            _deployConfig.checkpointDuration < minCheckpointDuration ||
            _deployConfig.checkpointDuration > maxCheckpointDuration ||
            _deployConfig.checkpointDuration % checkpointDurationResolution != 0
        ) {
            revert IHyperdrive.InvalidCheckpointDuration();
        }

        // Ensure that the specified checkpoint duration is within the minimum
        // and maximum position durations and is a multiple of the specified
        // checkpoint duration.
        if (
            _deployConfig.positionDuration < minPositionDuration ||
            _deployConfig.positionDuration > maxPositionDuration ||
            _deployConfig.positionDuration % _deployConfig.checkpointDuration !=
            0
        ) {
            revert IHyperdrive.InvalidPositionDuration();
        }

        // Ensure that the specified fees are within the minimum and maximum fees.
        if (
            _deployConfig.fees.curve > _maxFees.curve ||
            _deployConfig.fees.flat > _maxFees.flat ||
            _deployConfig.fees.governanceLP > _maxFees.governanceLP ||
            _deployConfig.fees.governanceZombie > _maxFees.governanceZombie ||
            _deployConfig.fees.curve < _minFees.curve ||
            _deployConfig.fees.flat < _minFees.flat ||
            _deployConfig.fees.governanceLP < _minFees.governanceLP ||
            _deployConfig.fees.governanceZombie < _minFees.governanceZombie
        ) {
            revert IHyperdrive.InvalidFees();
        }

        // Ensure that the linker factory, linker code hash, fee collector,
        // and governance addresses aren't set. This ensures that the
        // deployer isn't trying to set these values.
        if (
            _deployConfig.linkerFactory != address(0) ||
            _deployConfig.linkerCodeHash != bytes32(0) ||
            _deployConfig.feeCollector != address(0) ||
            _deployConfig.governance != address(0)
        ) {
            revert IHyperdrive.InvalidDeployConfig();
        }

        // Override the config values to the default values set by governance.
        // The factory assumes the governance role during deployment so that it
        // can set up some initial values; however the governance role will
        // ultimately be transferred to the hyperdrive governance address.
        _deployConfig.linkerFactory = linkerFactory;
        _deployConfig.linkerCodeHash = linkerCodeHash;
        _deployConfig.feeCollector = feeCollector;
        _deployConfig.governance = address(this);

        // Deploy the Hyperdrive instance with the specified Hyperdrive
        // deployer.
        IHyperdrive hyperdrive = IHyperdrive(
            IDeployerCoordinator(_deployerCoordinator).deploy(
                _deployConfig,
                _extraData
            )
        );

        // Add this instance to the registry and emit an event with the
        // deployment configuration.
        isOfficial[address(hyperdrive)] = versionCounter;
        _deployConfig.governance = hyperdriveGovernance;
        emit Deployed(
            versionCounter,
            address(hyperdrive),
            _deployConfig,
            _extraData
        );

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
            ERC20(address(_deployConfig.baseToken)).safeTransferFrom(
                msg.sender,
                address(this),
                _contribution
            );
            ERC20(address(_deployConfig.baseToken)).safeApprove(
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
                revert IHyperdrive.TransferFailed();
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
            revert IHyperdrive.InvalidIndexes();
        }
        if (endIndex > _instances.length) {
            revert IHyperdrive.EndIndexTooLarge();
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
            revert IHyperdrive.InvalidIndexes();
        }
        if (endIndex > _deployerCoordinators.length) {
            revert IHyperdrive.EndIndexTooLarge();
        }

        // Return the range of instances.
        range = new address[](endIndex - startIndex + 1);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            range[i - startIndex] = _deployerCoordinators[i];
        }
    }
}
