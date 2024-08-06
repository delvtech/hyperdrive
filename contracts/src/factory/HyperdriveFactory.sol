// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../interfaces/IHyperdriveDeployerCoordinator.sol";
import { IHyperdriveFactory } from "../interfaces/IHyperdriveFactory.sol";
import { FixedPointMath, ONE } from "../libraries/FixedPointMath.sol";
import { HYPERDRIVE_FACTORY_KIND, VERSION } from "../libraries/Constants.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";

/// @author DELV
/// @title HyperdriveFactory
/// @notice Deploys hyperdrive instances and initializes them. It also holds a
///         registry of all deployed hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveFactory is IHyperdriveFactory {
    using FixedPointMath for uint256;

    /// @notice The factory's name.
    string public name;

    /// @notice The factory's kind.
    string public constant kind = HYPERDRIVE_FACTORY_KIND;

    /// @notice The factory's version.
    string public constant version = VERSION;

    /// @dev Signifies an unlocked receive function, used by isReceiveLocked
    uint256 private constant RECEIVE_UNLOCKED = 1;

    /// @dev Signifies a locked receive function, used by isReceiveLocked
    uint256 private constant RECEIVE_LOCKED = 2;

    /// @dev Locks the receive function. This can be used to prevent stuck ether
    ///      from ending up in the contract but still allowing refunds to be
    ///      received. Defaults to `RECEIVE_LOCKED`
    uint256 private receiveLockState = RECEIVE_LOCKED;

    /// @notice The governance address that updates the factory's configuration
    ///         and can add or remove deployer coordinators.
    address public governance;

    /// @notice The deployer coordinator manager that can add or remove deployer
    ///         coordinators.
    address public deployerCoordinatorManager;

    /// @notice The governance address used when new instances are deployed.
    address public hyperdriveGovernance;

    /// @notice The linker factory used when new instances are deployed.
    address public linkerFactory;

    /// @notice The linker code hash used when new instances are deployed.
    bytes32 public linkerCodeHash;

    /// @notice The fee collector used when new instances are deployed.
    address public feeCollector;

    /// @notice The sweep collector used when new instances are deployed.
    address public sweepCollector;

    /// @dev The address that will reward checkpoint minters.
    address public checkpointRewarder;

    /// @notice The resolution for the checkpoint duration. Every checkpoint
    ///         duration must be a multiple of this resolution.
    uint256 public checkpointDurationResolution;

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

    /// @notice The minimum circuit breaker delta that can be used by
    ///         new deployments.
    uint256 public minCircuitBreakerDelta;

    /// @notice The maximum circuit breaker delta that can be used by
    ///         new deployments.
    uint256 public maxCircuitBreakerDelta;

    /// @notice The minimum fixed APR that can be used by new deployments.
    uint256 public minFixedAPR;

    /// @notice The maximum fixed APR that can be used by new deployments.
    uint256 public maxFixedAPR;

    /// @notice The minimum time stretch APR that can be used by new deployments.
    uint256 public minTimeStretchAPR;

    /// @notice The maximum time stretch APR that can be used by new deployments.
    uint256 public maxTimeStretchAPR;

    /// @notice The minimum fee parameters that can be used by new deployments.
    IHyperdrive.Fees internal _minFees;

    /// @notice The maximum fee parameters that can be used by new deployments.
    IHyperdrive.Fees internal _maxFees;

    /// @notice The defaultPausers used when new instances are deployed.
    address[] internal _defaultPausers;

    struct FactoryConfig {
        /// @dev The address which can update a factory.
        address governance;
        /// @dev The address which can add and remove deployer coordinators.
        address deployerCoordinatorManager;
        /// @dev The address which is set as the governor of hyperdrive.
        address hyperdriveGovernance;
        /// @dev The default addresses which will be set to have the pauser role.
        address[] defaultPausers;
        /// @dev The recipient of governance fees from new deployments.
        address feeCollector;
        /// @dev The recipient of swept tokens from new deployments.
        address sweepCollector;
        /// @dev The address that will reward checkpoint minters.
        address checkpointRewarder;
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
        /// @dev The minimum circuit breaker delta that can be used in new
        ///      deployments.
        uint256 minCircuitBreakerDelta;
        /// @dev The maximum circuit breaker delta that can be used in new
        ///      deployments.
        uint256 maxCircuitBreakerDelta;
        /// @dev The minimum fixed APR that can be used in new deployments.
        uint256 minFixedAPR;
        /// @dev The maximum fixed APR that can be used in new deployments.
        uint256 maxFixedAPR;
        /// @dev The minimum time stretch APR that can be used in new
        ///      deployments.
        uint256 minTimeStretchAPR;
        /// @dev The maximum time stretch APR that can be used in new
        ///      deployments.
        uint256 maxTimeStretchAPR;
        /// @dev The lower bound on the fees that can be used in new deployments.
        /// @dev Most of the fee parameters are used unmodified; however, the
        ///      flat fee parameter is interpreted as the minimum annualized
        ///      flat fee. This allows deployers to specify a smaller flat fee
        ///      than the minimum for terms shorter than a year and ensures that
        ///      they specify a larger flat fee than the minimum for terms
        ///      longer than a year.
        IHyperdrive.Fees minFees;
        /// @dev The upper bound on the fees that can be used in new deployments.
        /// @dev Most of the fee parameters are used unmodified; however, the
        ///      flat fee parameter is interpreted as the maximum annualized
        ///      flat fee. This ensures that deployers specify a smaller flat
        ///      fee than the maximum for terms shorter than a year and allows
        ///      deployers to specify a larger flat fee than the maximum for
        ///      terms longer than a year.
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

    /// @dev A mapping from deployed Hyperdrive instances to the deployer
    ///      coordinator that deployed them. This is useful for verifying the
    ///      bytecode that was used to deploy the instance.
    mapping(address instance => address deployCoordinator)
        public _instancesToDeployerCoordinators;

    /// @dev Array of all instances deployed by this factory.
    address[] internal _instances;

    /// @dev Mapping to check if an instance is in the _instances array.
    mapping(address => bool) public isInstance;

    /// @notice Initializes the factory.
    /// @param _factoryConfig Configuration of the Hyperdrive Factory.
    /// @param _name The factory's name.
    constructor(FactoryConfig memory _factoryConfig, string memory _name) {
        // Set the factory's name.
        name = _name;

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

        // Ensure that the minimum circuit breaker delta is greater than or
        // equal to the maximum circuit breaker delta.
        if (
            _factoryConfig.minCircuitBreakerDelta >
            _factoryConfig.maxCircuitBreakerDelta
        ) {
            revert IHyperdriveFactory.InvalidCircuitBreakerDelta();
        }
        minCircuitBreakerDelta = _factoryConfig.minCircuitBreakerDelta;
        maxCircuitBreakerDelta = _factoryConfig.maxCircuitBreakerDelta;

        // Ensure that the minimum fixed APR is less than or equal to the
        // maximum fixed APR.
        if (_factoryConfig.minFixedAPR > _factoryConfig.maxFixedAPR) {
            revert IHyperdriveFactory.InvalidFixedAPR();
        }
        minFixedAPR = _factoryConfig.minFixedAPR;
        maxFixedAPR = _factoryConfig.maxFixedAPR;

        // Ensure that the minimum time stretch APR is less than or equal to the
        // maximum time stretch APR.
        if (
            _factoryConfig.minTimeStretchAPR > _factoryConfig.maxTimeStretchAPR
        ) {
            revert IHyperdriveFactory.InvalidTimeStretchAPR();
        }
        minTimeStretchAPR = _factoryConfig.minTimeStretchAPR;
        maxTimeStretchAPR = _factoryConfig.maxTimeStretchAPR;

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
        deployerCoordinatorManager = _factoryConfig.deployerCoordinatorManager;
        hyperdriveGovernance = _factoryConfig.hyperdriveGovernance;
        feeCollector = _factoryConfig.feeCollector;
        sweepCollector = _factoryConfig.sweepCollector;
        checkpointRewarder = _factoryConfig.checkpointRewarder;
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

    /// @dev Ensure that the sender is either the governance address or the
    ///      deployer coordinator manager.
    modifier onlyDeployerCoordinatorManager() {
        if (
            msg.sender != governance && msg.sender != deployerCoordinatorManager
        ) {
            revert IHyperdriveFactory.Unauthorized();
        }
        _;
    }

    /// @notice Allows ether to be sent to the contract. This is gated by a lock
    ///         to prevent ether from becoming stuck in the contract.
    receive() external payable {
        if (receiveLockState == RECEIVE_LOCKED) {
            revert IHyperdriveFactory.ReceiveLocked();
        }
    }

    /// @notice Allows governance to transfer the governance role.
    /// @param _governance The new governance address.
    function updateGovernance(address _governance) external onlyGovernance {
        governance = _governance;
        emit GovernanceUpdated(_governance);
    }

    /// @notice Allows governance to change the deployer coordinator manager
    ///         address.
    /// @param _deployerCoordinatorManager The new deployer coordinator manager
    ///        address.
    function updateDeployerCoordinatorManager(
        address _deployerCoordinatorManager
    ) external onlyGovernance {
        deployerCoordinatorManager = _deployerCoordinatorManager;
        emit DeployerCoordinatorManagerUpdated(_deployerCoordinatorManager);
    }

    /// @notice Allows governance to change the hyperdrive governance address.
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

    /// @notice Allows governance to change the sweep collector address.
    /// @param _sweepCollector The new sweep collector address.
    function updateSweepCollector(
        address _sweepCollector
    ) external onlyGovernance {
        sweepCollector = _sweepCollector;
        emit SweepCollectorUpdated(_sweepCollector);
    }

    /// @notice Allows governance to change the checkpoint rewarder address.
    /// @param _checkpointRewarder The new checkpoint rewarder address.
    function updateCheckpointRewarder(
        address _checkpointRewarder
    ) external onlyGovernance {
        checkpointRewarder = _checkpointRewarder;
        emit CheckpointRewarderUpdated(_checkpointRewarder);
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

    /// @notice Allows governance to update the maximum circuit breaker delta.
    /// @param _maxCircuitBreakerDelta The new maximum circuit breaker delta.
    function updateMaxCircuitBreakerDelta(
        uint256 _maxCircuitBreakerDelta
    ) external onlyGovernance {
        // Ensure that the maximum circuit breaker delta is greater than or
        // equal to the minimum circuit breaker delta.
        if (_maxCircuitBreakerDelta < minCircuitBreakerDelta) {
            revert IHyperdriveFactory.InvalidMaxCircuitBreakerDelta();
        }

        // Update the maximum circuit breaker delta and emit an event.
        maxCircuitBreakerDelta = _maxCircuitBreakerDelta;
        emit MaxCircuitBreakerDeltaUpdated(_maxCircuitBreakerDelta);
    }

    /// @notice Allows governance to update the minimum circuit breaker delta.
    /// @param _minCircuitBreakerDelta The new minimum circuit breaker delta.
    function updateMinCircuitBreakerDelta(
        uint256 _minCircuitBreakerDelta
    ) external onlyGovernance {
        // Ensure that the minimum position duration is greater than or equal
        // to the maximum checkpoint duration and is a multiple of the
        // checkpoint duration resolution. Also ensure that the minimum position
        // duration is less than or equal to the maximum position duration.
        if (_minCircuitBreakerDelta > maxCircuitBreakerDelta) {
            revert IHyperdriveFactory.InvalidMinCircuitBreakerDelta();
        }

        // Update the minimum circuit breaker delta and emit an event.
        minCircuitBreakerDelta = _minCircuitBreakerDelta;
        emit MinCircuitBreakerDeltaUpdated(_minCircuitBreakerDelta);
    }

    /// @notice Allows governance to update the maximum fixed APR.
    /// @param _maxFixedAPR The new maximum fixed APR.
    function updateMaxFixedAPR(uint256 _maxFixedAPR) external onlyGovernance {
        // Ensure that the maximum fixed APR is greater than or equal to the
        // minimum fixed APR.
        if (_maxFixedAPR < minFixedAPR) {
            revert IHyperdriveFactory.InvalidMaxFixedAPR();
        }

        // Update the maximum fixed APR and emit an event.
        maxFixedAPR = _maxFixedAPR;
        emit MaxFixedAPRUpdated(_maxFixedAPR);
    }

    /// @notice Allows governance to update the minimum fixed APR.
    /// @param _minFixedAPR The new minimum fixed APR.
    function updateMinFixedAPR(uint256 _minFixedAPR) external onlyGovernance {
        // Ensure that the minimum fixed APR is less than or equal to the
        // maximum fixed APR.
        if (_minFixedAPR > maxFixedAPR) {
            revert IHyperdriveFactory.InvalidMinFixedAPR();
        }

        // Update the minimum fixed APR and emit an event.
        minFixedAPR = _minFixedAPR;
        emit MinFixedAPRUpdated(_minFixedAPR);
    }

    /// @notice Allows governance to update the maximum time stretch APR.
    /// @param _maxTimeStretchAPR The new maximum time stretch APR.
    function updateMaxTimeStretchAPR(
        uint256 _maxTimeStretchAPR
    ) external onlyGovernance {
        // Ensure that the maximum time stretch APR is greater than or equal
        // to the minimum time stretch APR.
        if (_maxTimeStretchAPR < minTimeStretchAPR) {
            revert IHyperdriveFactory.InvalidMaxTimeStretchAPR();
        }

        // Update the maximum time stretch APR and emit an event.
        maxTimeStretchAPR = _maxTimeStretchAPR;
        emit MaxTimeStretchAPRUpdated(_maxTimeStretchAPR);
    }

    /// @notice Allows governance to update the minimum time stretch APR.
    /// @param _minTimeStretchAPR The new minimum time stretch APR.
    function updateMinTimeStretchAPR(
        uint256 _minTimeStretchAPR
    ) external onlyGovernance {
        // Ensure that the minimum time stretch APR is less than or equal
        // to the maximum time stretch APR.
        if (_minTimeStretchAPR > maxTimeStretchAPR) {
            revert IHyperdriveFactory.InvalidMinTimeStretchAPR();
        }

        // Update the minimum time stretch APR and emit an event.
        minTimeStretchAPR = _minTimeStretchAPR;
        emit MinTimeStretchAPRUpdated(_minTimeStretchAPR);
    }

    /// @notice Allows governance to update the maximum fee parameters.
    /// @param __maxFees The new maximum fee parameters.
    function updateMaxFees(
        IHyperdrive.Fees calldata __maxFees
    ) external onlyGovernance {
        // Ensure that the max fees are each less than or equal to 100% and that
        // the max fees are each greater than or equal to the corresponding min
        // fee.
        IHyperdrive.Fees memory minFees_ = _minFees;
        if (
            __maxFees.curve > ONE ||
            __maxFees.flat > ONE ||
            __maxFees.governanceLP > ONE ||
            __maxFees.governanceZombie > ONE ||
            __maxFees.curve < minFees_.curve ||
            __maxFees.flat < minFees_.flat ||
            __maxFees.governanceLP < minFees_.governanceLP ||
            __maxFees.governanceZombie < minFees_.governanceZombie
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
        IHyperdrive.Fees memory maxFees_ = _maxFees;
        if (
            __minFees.curve > maxFees_.curve ||
            __minFees.flat > maxFees_.flat ||
            __minFees.governanceLP > maxFees_.governanceLP ||
            __minFees.governanceZombie > maxFees_.governanceZombie
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
    ) external onlyDeployerCoordinatorManager {
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
    ) external onlyDeployerCoordinatorManager {
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
    /// @param __name The name of the Hyperdrive pool.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains data necessary for the
    ///        specific deployer.
    /// @param _contribution The contribution amount in base to the pool.
    /// @param _fixedAPR The fixed APR used to initialize the pool.
    /// @param _timeStretchAPR The time stretch APR used to initialize the pool.
    /// @param _options The options for the `initialize` call.
    /// @param _salt The create2 salt to use for the deployment.
    /// @return The hyperdrive address deployed.
    function deployAndInitialize(
        bytes32 _deploymentId,
        address _deployerCoordinator,
        string memory __name,
        IHyperdrive.PoolDeployConfig memory _config,
        bytes memory _extraData,
        uint256 _contribution,
        uint256 _fixedAPR,
        uint256 _timeStretchAPR,
        IHyperdrive.Options memory _options,
        bytes32 _salt
    ) external payable returns (IHyperdrive) {
        // Ensure that the deployer coordinator has been registered.
        if (!isDeployerCoordinator[_deployerCoordinator]) {
            revert IHyperdriveFactory.InvalidDeployerCoordinator();
        }

        // Override the config values to the default values set by governance
        // and ensure that the config is valid.
        _overrideConfig(_config, _fixedAPR, _timeStretchAPR);

        // Deploy the Hyperdrive instance with the specified deployer
        // coordinator.
        IHyperdrive hyperdrive = IHyperdrive(
            IHyperdriveDeployerCoordinator(_deployerCoordinator)
                .deployHyperdrive(
                    // NOTE: We hash the deployer's address into the deployment ID
                    // to prevent their deployment from being front-run.
                    keccak256(abi.encode(msg.sender, _deploymentId)),
                    __name,
                    _config,
                    _extraData,
                    _salt
                )
        );

        // Add this instance to the registry and emit an event with the
        // deployment configuration.
        _instancesToDeployerCoordinators[
            address(hyperdrive)
        ] = _deployerCoordinator;
        _config.governance = hyperdriveGovernance;
        emit Deployed(
            _deployerCoordinator,
            address(hyperdrive),
            __name,
            _config,
            _extraData
        );

        // Add the newly deployed Hyperdrive instance to the registry.
        _instances.push(address(hyperdrive));
        isInstance[address(hyperdrive)] = true;

        // Initialize the Hyperdrive instance.
        receiveLockState = RECEIVE_UNLOCKED;
        IHyperdriveDeployerCoordinator(_deployerCoordinator).initialize{
            value: msg.value
        }(
            // NOTE: We hash the deployer's address into the deployment ID
            // to prevent their deployment from being front-run.
            keccak256(abi.encode(msg.sender, _deploymentId)),
            msg.sender,
            _contribution,
            _fixedAPR,
            _options
        );
        receiveLockState = RECEIVE_LOCKED;

        // Set the default pausers and transfer the governance status to the
        // hyperdrive governance address.
        for (uint256 i = 0; i < _defaultPausers.length; i++) {
            hyperdrive.setPauser(_defaultPausers[i], true);
        }
        hyperdrive.setGovernance(hyperdriveGovernance);

        // Refund any excess ether that was sent to this contract.
        uint256 refund = address(this).balance;
        if (refund > 0) {
            (bool success, ) = payable(msg.sender).call{ value: refund }("");
            if (!success) {
                revert IHyperdriveFactory.TransferFailed();
            }
        }

        return hyperdrive;
    }

    /// @notice Deploys a Hyperdrive target with the factory's configuration.
    /// @param _deploymentId The deployment ID to use when deploying the pool.
    /// @param _deployerCoordinator The deployer coordinator to use in this
    ///        deployment.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains data necessary for the
    ///        specific deployer.
    /// @param _fixedAPR The fixed APR used to initialize the pool.
    /// @param _timeStretchAPR The time stretch APR used to initialize the pool.
    /// @param _targetIndex The index of the target to deploy.
    /// @param _salt The create2 salt to use for the deployment.
    /// @return The target address deployed.
    function deployTarget(
        bytes32 _deploymentId,
        address _deployerCoordinator,
        IHyperdrive.PoolDeployConfig memory _config,
        bytes memory _extraData,
        uint256 _fixedAPR,
        uint256 _timeStretchAPR,
        uint256 _targetIndex,
        bytes32 _salt
    ) external returns (address) {
        // Ensure that the deployer coordinator has been registered.
        if (!isDeployerCoordinator[_deployerCoordinator]) {
            revert IHyperdriveFactory.InvalidDeployerCoordinator();
        }

        // Override the config values to the default values set by governance
        // and ensure that the config is valid.
        _overrideConfig(_config, _fixedAPR, _timeStretchAPR);

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
    /// @param _index The index of the instance to get.
    /// @return The instance at the specified index.
    function getInstanceAtIndex(
        uint256 _index
    ) external view returns (address) {
        return _instances[_index];
    }

    /// @notice Returns the _instances array according to specified indices.
    /// @param _startIndex The starting index of the instances to get (inclusive).
    /// @param _endIndex The ending index of the instances to get (exclusive).
    /// @return range The resulting custom portion of the _instances array.
    function getInstancesInRange(
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (address[] memory range) {
        // If the indexes are malformed, revert.
        if (_startIndex >= _endIndex) {
            revert IHyperdriveFactory.InvalidIndexes();
        }
        if (_endIndex > _instances.length) {
            revert IHyperdriveFactory.EndIndexTooLarge();
        }

        // Return the range of instances.
        range = new address[](_endIndex - _startIndex);
        for (uint256 i = _startIndex; i < _endIndex; i++) {
            unchecked {
                range[i - _startIndex] = _instances[i];
            }
        }
    }

    /// @notice Gets the number of deployer coordinators registered in this
    ///         factory.
    /// @return The number of deployer coordinators deployed by this factory.
    function getNumberOfDeployerCoordinators() external view returns (uint256) {
        return _deployerCoordinators.length;
    }

    /// @notice Gets the deployer coordinator at the specified index.
    /// @param _index The index of the deployer coordinator to get.
    /// @return The deployer coordinator at the specified index.
    function getDeployerCoordinatorAtIndex(
        uint256 _index
    ) external view returns (address) {
        return _deployerCoordinators[_index];
    }

    /// @notice Returns the deployer coordinators with an index between the
    ///         starting and ending indexes.
    /// @param _startIndex The starting index (inclusive).
    /// @param _endIndex The ending index (exclusive).
    /// @return range The deployer coordinators within the specified range.
    function getDeployerCoordinatorsInRange(
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (address[] memory range) {
        // If the indexes are malformed, revert.
        if (_startIndex >= _endIndex) {
            revert IHyperdriveFactory.InvalidIndexes();
        }
        if (_endIndex > _deployerCoordinators.length) {
            revert IHyperdriveFactory.EndIndexTooLarge();
        }

        // Return the range of instances.
        range = new address[](_endIndex - _startIndex);
        for (uint256 i = _startIndex; i < _endIndex; i++) {
            unchecked {
                range[i - _startIndex] = _deployerCoordinators[i];
            }
        }
    }

    /// @notice Gets the deployer coordinators that deployed a list of instances.
    /// @param __instances The instances.
    /// @return coordinators The deployer coordinators.
    function getDeployerCoordinatorByInstances(
        address[] calldata __instances
    ) external view returns (address[] memory coordinators) {
        coordinators = new address[](_instances.length);
        for (uint256 i = 0; i < __instances.length; i++) {
            coordinators[i] = _instancesToDeployerCoordinators[__instances[i]];
        }
        return coordinators;
    }

    /// @dev Overrides the config values to the default values set by
    ///      governance. In the process of overriding these parameters, this
    ///      verifies that the specified config is valid.
    /// @param _config The config to override.
    /// @param _fixedAPR The fixed APR to use in the override.
    /// @param _timeStretchAPR The time stretch APR to use in the override.
    function _overrideConfig(
        IHyperdrive.PoolDeployConfig memory _config,
        uint256 _fixedAPR,
        uint256 _timeStretchAPR
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

        // Ensure that the specified circuit breaker delta is within the minimum
        // and maximum circuit breaker deltas.
        if (
            _config.circuitBreakerDelta < minCircuitBreakerDelta ||
            _config.circuitBreakerDelta > maxCircuitBreakerDelta
        ) {
            revert IHyperdriveFactory.InvalidCircuitBreakerDelta();
        }

        // Ensure that the specified fees are within the minimum and maximum
        // fees. The flat fee is annualized so that it is consistent across all
        // term lengths.
        if (
            _config.fees.curve > _maxFees.curve ||
            // NOTE: Round up here to make the check stricter
            ///      since truthy values causes revert.
            _config.fees.flat.mulDivUp(365 days, _config.positionDuration) >
            _maxFees.flat ||
            _config.fees.governanceLP > _maxFees.governanceLP ||
            _config.fees.governanceZombie > _maxFees.governanceZombie ||
            _config.fees.curve < _minFees.curve ||
            // NOTE: Round down here to make the check stricter
            ///      since truthy values causes revert.
            _config.fees.flat.mulDivDown(365 days, _config.positionDuration) <
            _minFees.flat ||
            _config.fees.governanceLP < _minFees.governanceLP ||
            _config.fees.governanceZombie < _minFees.governanceZombie
        ) {
            revert IHyperdriveFactory.InvalidFees();
        }

        // Ensure that specified fixed APR is within the minimum and maximum
        // fixed APRs.
        if (_fixedAPR < minFixedAPR || _fixedAPR > maxFixedAPR) {
            revert IHyperdriveFactory.InvalidFixedAPR();
        }

        // Calculate the time stretch using the provided APR and ensure that
        // the time stretch falls within a safe range and the guards specified
        // by governance.
        uint256 lowerBound = _fixedAPR.divDown(2e18).max(0.005e18);
        if (
            _timeStretchAPR < minTimeStretchAPR.max(lowerBound) ||
            _timeStretchAPR >
            maxTimeStretchAPR.min(_fixedAPR.max(lowerBound).mulDown(2e18))
        ) {
            revert IHyperdriveFactory.InvalidTimeStretchAPR();
        }
        uint256 timeStretch = HyperdriveMath.calculateTimeStretch(
            _timeStretchAPR,
            _config.positionDuration
        );

        // Ensure that the linker factory, linker code hash, fee collector, and
        // governance addresses are set to the expected values. This ensures
        // that the deployer is aware of the correct values. The time stretch
        // should be set to zero to signal that the deployer is aware that it
        // will be overwritten.
        if (
            _config.linkerFactory != linkerFactory ||
            _config.linkerCodeHash != linkerCodeHash ||
            _config.feeCollector != feeCollector ||
            _config.sweepCollector != sweepCollector ||
            _config.checkpointRewarder != checkpointRewarder ||
            _config.governance != hyperdriveGovernance ||
            _config.timeStretch != 0
        ) {
            revert IHyperdriveFactory.InvalidDeployConfig();
        }

        // Override the config values to the default values set by governance.
        // The factory assumes the governance role during deployment so that it
        // can set up some initial values; however the governance role will
        // ultimately be transferred to the hyperdrive governance address.
        _config.governance = address(this);
        _config.timeStretch = timeStretch;
    }
}
