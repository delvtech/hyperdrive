// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IHyperdriveFactory {
    /// Events ///

    /// @notice Emitted when a Hyperdrive pool is deployed.
    event Deployed(
        address indexed deployerCoordinator,
        address hyperdrive,
        string name,
        IHyperdrive.PoolDeployConfig config,
        bytes extraData
    );

    /// @notice Emitted when a deployer coordinator is added.
    event DeployerCoordinatorAdded(address indexed deployerCoordinator);

    /// @notice Emitted when a deployer coordinator is removed.
    event DeployerCoordinatorRemoved(address indexed deployerCoordinator);

    /// @notice Emitted when the list of default pausers is updated.
    event DefaultPausersUpdated(address[] newDefaultPausers);

    /// @notice Emitted when the fee collector used in new deployments is updated.
    event FeeCollectorUpdated(address indexed newFeeCollector);

    /// @notice Emitted when the sweep collector used in new deployments is
    ///         updated.
    event SweepCollectorUpdated(address indexed newSweepCollector);

    /// @notice Emitted when the checkpoint rewarder used in new deployments is
    ///         updated.
    event CheckpointRewarderUpdated(address indexed newCheckpointRewarder);

    /// @notice Emitted when the factory's governance is updated.
    event GovernanceUpdated(address indexed governance);

    /// @notice Emitted when the deployer coordinator manager is updated.
    event DeployerCoordinatorManagerUpdated(
        address indexed deployerCoordinatorManager
    );

    /// @notice Emitted when the governance address used in new deployments is
    ///         updated.
    event HyperdriveGovernanceUpdated(address indexed hyperdriveGovernance);

    /// @notice Emitted when the linker factory used in new deployments is
    ///         updated.
    event LinkerFactoryUpdated(address indexed newLinkerFactory);

    /// @notice Emitted when the linker code hash used in new deployments is
    ///         updated.
    event LinkerCodeHashUpdated(bytes32 indexed newLinkerCodeHash);

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

    /// @notice Emitted when the maximum circuit breaker delta is updated.
    event MaxCircuitBreakerDeltaUpdated(uint256 newMaxCircuitBreakerDelta);

    /// @notice Emitted when the minimum circuit breaker delta is updated.
    event MinCircuitBreakerDeltaUpdated(uint256 newMinCircuitBreakerDelta);

    /// @notice Emitted when the maximum fixed APR is updated.
    event MaxFixedAPRUpdated(uint256 newMaxFixedAPR);

    /// @notice Emitted when the minimum fixed APR is updated.
    event MinFixedAPRUpdated(uint256 newMinFixedAPR);

    /// @notice Emitted when the maximum time stretch APR is updated.
    event MaxTimeStretchAPRUpdated(uint256 newMaxTimeStretchAPR);

    /// @notice Emitted when the minimum time stretch APR is updated.
    event MinTimeStretchAPRUpdated(uint256 newMinTimeStretchAPR);

    /// @notice Emitted when the maximum fees are updated.
    event MaxFeesUpdated(IHyperdrive.Fees newMaxFees);

    /// @notice Emitted when the minimum fees are updated.
    event MinFeesUpdated(IHyperdrive.Fees newMinFees);

    /// Errors ///

    /// @notice Thrown when governance attempts to add a deployer coordinator
    ///         that has already been added.
    error DeployerCoordinatorAlreadyAdded();

    /// @notice Thrown when governance attempts to remove a deployer coordinator
    ///         that was never added.
    error DeployerCoordinatorNotAdded();

    /// @notice Thrown when governance attempts to remove a deployer coordinator
    ///         but specifies the wrong index within the list of deployer
    ///         coordinators.
    error DeployerCoordinatorIndexMismatch();

    /// @notice Thrown when the ending index of a range is larger than the
    ///         underlying list.
    error EndIndexTooLarge();

    /// @notice Thrown when the checkpoint duration supplied to `deployTarget`
    ///         or `deployAndInitialize` isn't a multiple of the checkpoint
    ///         duration resolution or isn't within the range specified by the
    ///         minimum and maximum checkpoint durations.
    error InvalidCheckpointDuration();

    /// @notice Thrown when governance attempts to set the checkpoint duration
    ///         resolution to a value that doesn't evenly divide the minimum
    ///         checkpoint duration, maximum checkpoint duration, minimum
    ///         position duration, or maximum position duration.
    error InvalidCheckpointDurationResolution();

    /// @notice Thrown when the deploy configuration passed to
    ///         `deployAndInitialize` has fields set that will be overridden by
    ///         governance.
    error InvalidDeployConfig();

    /// @notice Thrown when the deployer coordinator passed to
    ///         `deployAndInitialize` hasn't been added to the factory.
    error InvalidDeployerCoordinator();

    /// @notice Thrown when the fee parameters passed to `deployAndInitialize`
    ///         aren't within the range specified by the minimum and maximum
    ///         fees.
    error InvalidFees();

    /// @notice Thrown when the starting index of a range is larger than the
    ///         ending index.
    error InvalidIndexes();

    /// @notice Thrown when governance attempts to set one of the maximum fee
    ///         parameters to a smaller value than the corresponding minimum fee
    ///         parameter.
    error InvalidMaxFees();

    /// @notice Thrown when governance attempts to set one of the minimum fee
    ///         parameters to a larger value than the corresponding maximum fee
    ///         parameter.
    error InvalidMinFees();

    /// @notice Thrown when governance attempts to set the maximum checkpoint
    ///         duration to a value that isn't a multiple of the checkpoint
    ///         duration resolution or is smaller than the minimum checkpoint
    ///         duration.
    error InvalidMaxCheckpointDuration();

    /// @notice Thrown when governance attempts to set the minimum checkpoint
    ///         duration to a value that isn't a multiple of the checkpoint
    ///         duration resolution or is larger than the maximum checkpoint
    ///         duration.
    error InvalidMinCheckpointDuration();

    /// @notice Thrown when governance attempts to set the maximum position
    ///         duration to a value that isn't a multiple of the checkpoint
    ///         duration resolution or is smaller than the minimum position
    ///         duration.
    error InvalidMaxPositionDuration();

    /// @notice Thrown when governance attempts to set the minimum position
    ///         duration to a value that isn't a multiple of the checkpoint
    ///         duration resolution or is larger than the maximum position
    ///         duration.
    error InvalidMinPositionDuration();

    /// @notice Thrown when the position duration passed to `deployAndInitialize`
    ///         doesn't fall within the range specified by the minimum and
    ///         maximum position durations.
    error InvalidPositionDuration();

    /// @notice Thrown when governance attempts to set the maximum circuit
    ///         breaker delta to a value that is less than the minimum
    ///         circuit breaker delta.
    error InvalidMaxCircuitBreakerDelta();

    /// @notice Thrown when governance attempts to set the minimum circuit
    ///         breaker delta to a value that is greater than the maximum
    ///         circuit breaker delta.
    error InvalidMinCircuitBreakerDelta();

    /// @notice Thrown when the circuit breaker delta passed to
    ///         `deployAndInitialize` doesn't fall within the range specified by
    ///         the minimum and maximum circuit breaker delta.
    error InvalidCircuitBreakerDelta();

    /// @notice Thrown when governance attempts to set the maximum fixed APR to
    ///         a value that is smaller than the minimum fixed APR.
    error InvalidMaxFixedAPR();

    /// @notice Thrown when governance attempts to set the minimum fixed APR to
    ///         a value that is larger than the maximum fixed APR.
    error InvalidMinFixedAPR();

    /// @notice Thrown when the fixed APR passed to `deployAndInitialize` isn't
    ///         within the range specified by the minimum and maximum fixed
    ///         APRs.
    error InvalidFixedAPR();

    /// @notice Thrown when governance attempts to set the maximum time stretch
    ///         APR to a value that is smaller than the minimum time stretch
    ///         APR.
    error InvalidMaxTimeStretchAPR();

    /// @notice Thrown when governance attempts to set the minimum time stretch
    ///         APR to a value that is larger than the maximum time stretch
    ///         APR.
    error InvalidMinTimeStretchAPR();

    /// @notice Thrown when a time stretch APR is passed to `deployAndInitialize`
    ///         that isn't within the range specified by the minimum and maximum
    ///         time stretch APRs or doesn't satisfy the lower and upper safe
    ///         bounds implied by the fixed APR.
    error InvalidTimeStretchAPR();

    /// @notice Thrown when ether is sent to the factory when `receive` is
    ///         locked.
    error ReceiveLocked();

    /// @notice Thrown when an ether transfer fails.
    error TransferFailed();

    /// @notice Thrown when an unauthorized caller attempts to update one of the
    ///         governance administered parameters.
    error Unauthorized();

    /// Functions ///

    /// @notice Allows governance to transfer the governance role.
    /// @param _governance The new governance address.
    function updateGovernance(address _governance) external;

    /// @notice Allows governance to change the deployer coordinator manager
    ///         address.
    /// @param _deployerCoordinatorManager The new deployer coordinator manager
    ///        address.
    function updateDeployerCoordinatorManager(
        address _deployerCoordinatorManager
    ) external;

    /// @notice Allows governance to change the hyperdrive governance address.
    /// @param _hyperdriveGovernance The new hyperdrive governance address.
    function updateHyperdriveGovernance(address _hyperdriveGovernance) external;

    /// @notice Allows governance to change the linker factory.
    /// @param _linkerFactory The new linker factory.
    function updateLinkerFactory(address _linkerFactory) external;

    /// @notice Allows governance to change the linker code hash. This allows
    ///         governance to update the implementation of the ERC20Forwarder.
    /// @param _linkerCodeHash The new linker code hash.
    function updateLinkerCodeHash(bytes32 _linkerCodeHash) external;

    /// @notice Allows governance to change the fee collector address.
    /// @param _feeCollector The new fee collector address.
    function updateFeeCollector(address _feeCollector) external;

    /// @notice Allows governance to change the sweep collector address.
    /// @param _sweepCollector The new sweep collector address.
    function updateSweepCollector(address _sweepCollector) external;

    /// @notice Allows governance to change the checkpoint rewarder address.
    /// @param _checkpointRewarder The new checkpoint rewarder address.
    function updateCheckpointRewarder(address _checkpointRewarder) external;

    /// @notice Allows governance to change the checkpoint duration resolution.
    /// @param _checkpointDurationResolution The new checkpoint duration
    ///        resolution.
    function updateCheckpointDurationResolution(
        uint256 _checkpointDurationResolution
    ) external;

    /// @notice Allows governance to update the maximum checkpoint duration.
    /// @param _maxCheckpointDuration The new maximum checkpoint duration.
    function updateMaxCheckpointDuration(
        uint256 _maxCheckpointDuration
    ) external;

    /// @notice Allows governance to update the minimum checkpoint duration.
    /// @param _minCheckpointDuration The new minimum checkpoint duration.
    function updateMinCheckpointDuration(
        uint256 _minCheckpointDuration
    ) external;

    /// @notice Allows governance to update the maximum position duration.
    /// @param _maxPositionDuration The new maximum position duration.
    function updateMaxPositionDuration(uint256 _maxPositionDuration) external;

    /// @notice Allows governance to update the minimum position duration.
    /// @param _minPositionDuration The new minimum position duration.
    function updateMinPositionDuration(uint256 _minPositionDuration) external;

    /// @notice Allows governance to update the maximum circuit breaker delta.
    /// @param _maxCircuitBreakerDelta The new maximum circuit breaker delta.
    function updateMaxCircuitBreakerDelta(
        uint256 _maxCircuitBreakerDelta
    ) external;

    /// @notice Allows governance to update the minimum circuit breaker delta.
    /// @param _minCircuitBreakerDelta The new minimum circuit breaker delta.
    function updateMinCircuitBreakerDelta(
        uint256 _minCircuitBreakerDelta
    ) external;

    /// @notice Allows governance to update the maximum fixed APR.
    /// @param _maxFixedAPR The new maximum fixed APR.
    function updateMaxFixedAPR(uint256 _maxFixedAPR) external;

    /// @notice Allows governance to update the minimum fixed APR.
    /// @param _minFixedAPR The new minimum fixed APR.
    function updateMinFixedAPR(uint256 _minFixedAPR) external;

    /// @notice Allows governance to update the maximum time stretch APR.
    /// @param _maxTimeStretchAPR The new maximum time stretch APR.
    function updateMaxTimeStretchAPR(uint256 _maxTimeStretchAPR) external;

    /// @notice Allows governance to update the minimum time stretch APR.
    /// @param _minTimeStretchAPR The new minimum time stretch APR.
    function updateMinTimeStretchAPR(uint256 _minTimeStretchAPR) external;

    /// @notice Allows governance to update the maximum fee parameters.
    /// @param __maxFees The new maximum fee parameters.
    function updateMaxFees(IHyperdrive.Fees calldata __maxFees) external;

    /// @notice Allows governance to update the minimum fee parameters.
    /// @param __minFees The new minimum fee parameters.
    function updateMinFees(IHyperdrive.Fees calldata __minFees) external;

    /// @notice Allows governance to change the default pausers.
    /// @param _defaultPausers_ The new list of default pausers.
    function updateDefaultPausers(address[] calldata _defaultPausers_) external;

    /// @notice Allows governance to add a new deployer coordinator.
    /// @param _deployerCoordinator The new deployer coordinator.
    function addDeployerCoordinator(address _deployerCoordinator) external;

    /// @notice Allows governance to remove an existing deployer coordinator.
    /// @param _deployerCoordinator The deployer coordinator to remove.
    /// @param _index The index of the deployer coordinator to remove.
    function removeDeployerCoordinator(
        address _deployerCoordinator,
        uint256 _index
    ) external;

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
    ) external payable returns (IHyperdrive);

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
    ) external returns (address);

    /// Getters ///

    /// @notice Gets the factory's name.
    /// @return The factory's name.
    function name() external view returns (string memory);

    /// @notice Gets the factory's kind.
    /// @return The factory's kind.
    function kind() external pure returns (string memory);

    /// @notice Gets the factory's version.
    /// @return The factory's version.
    function version() external pure returns (string memory);

    /// @notice Returns the governance address that updates the factory's
    ///         configuration.
    /// @return The factory's governance address.
    function governance() external view returns (address);

    /// @notice Returns the deployer coordinator manager address that can add or
    ///         remove deployer coordinators.
    /// @return The factory's deployer coordinator manager address.
    function deployerCoordinatorManager() external view returns (address);

    /// @notice Returns the governance address used when new instances are
    ///         deployed.
    /// @return The factory's hyperdrive governance address.
    function hyperdriveGovernance() external view returns (address);

    /// @notice Returns the linker factory used when new instances are deployed.
    /// @return The factory's linker factory.
    function linkerFactory() external view returns (address);

    /// @notice Returns the linker code hash used when new instances are
    ///         deployed.
    /// @return The factory's linker code hash.
    function linkerCodeHash() external view returns (bytes32);

    /// @notice Returns the fee collector used when new instances are deployed.
    /// @return The factory's fee collector.
    function feeCollector() external view returns (address);

    /// @notice Returns the sweep collector used when new instances are deployed.
    /// @return The factory's sweep collector.
    function sweepCollector() external view returns (address);

    /// @notice Returns the checkpoint rewarder used when new instances are
    ///         deployed.
    /// @return The factory's checkpoint rewarder.
    function checkpointRewarder() external view returns (address);

    /// @notice Returns the resolution for the checkpoint duration. Every
    ///         checkpoint duration must be a multiple of this resolution.
    /// @return The factory's checkpoint duration resolution.
    function checkpointDurationResolution() external view returns (uint256);

    /// @notice Returns the minimum checkpoint duration that can be used by new
    ///         deployments.
    /// @return The factory's minimum checkpoint duration.
    function minCheckpointDuration() external view returns (uint256);

    /// @notice Returns the maximum checkpoint duration that can be used by new
    ///         deployments.
    /// @return The factory's maximum checkpoint duration.
    function maxCheckpointDuration() external view returns (uint256);

    /// @notice Returns the minimum position duration that can be used by new
    ///         deployments.
    /// @return The factory's minimum position duration.
    function minPositionDuration() external view returns (uint256);

    /// @notice Returns the maximum position duration that can be used by new
    ///         deployments.
    /// @return The factory's maximum position duration.
    function maxPositionDuration() external view returns (uint256);

    /// @notice Returns the minimum circuit breaker delta that can be used by
    ///         new deployments.
    /// @return The factory's minimum circuit breaker delta.
    function minCircuitBreakerDelta() external view returns (uint256);

    /// @notice Returns the maximum circuit breaker delta that can be used by
    ///         new deployments.
    /// @return The factory's maximum circuit breaker delta.
    function maxCircuitBreakerDelta() external view returns (uint256);

    /// @notice Returns the minimum fixed APR that can be used by new
    ///         deployments.
    /// @return The factory's minimum fixed APR.
    function minFixedAPR() external view returns (uint256);

    /// @notice Returns the maximum fixed APR that can be used by new
    ///         deployments.
    /// @return The factory's maximum fixed APR.
    function maxFixedAPR() external view returns (uint256);

    /// @notice Returns the minimum time stretch APR that can be used by new
    ///         deployments.
    /// @return The factory's minimum time stretch APR.
    function minTimeStretchAPR() external view returns (uint256);

    /// @notice Returns the maximum time stretch APR that can be used by new
    ///         deployments.
    /// @return The factory's maximum time stretch APR.
    function maxTimeStretchAPR() external view returns (uint256);

    /// @notice Gets the max fees.
    /// @return The max fees.
    function maxFees() external view returns (IHyperdrive.Fees memory);

    /// @notice Gets the min fees.
    /// @return The min fees.
    function minFees() external view returns (IHyperdrive.Fees memory);

    /// @notice Gets the default pausers.
    /// @return The default pausers.
    function defaultPausers() external view returns (address[] memory);

    /// @notice Gets the number of instances deployed by this factory.
    /// @return The number of instances deployed by this factory.
    function getNumberOfInstances() external view returns (uint256);

    /// @notice Gets the instance at the specified index.
    /// @param _index The index of the instance to get.
    /// @return The instance at the specified index.
    function getInstanceAtIndex(uint256 _index) external view returns (address);

    /// @notice Returns the _instances array according to specified indices.
    /// @param _startIndex The starting index of the instances to get.
    /// @param _endIndex The ending index of the instances to get.
    /// @return range The resulting custom portion of the _instances array.
    function getInstancesInRange(
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (address[] memory range);

    /// @notice Returns a flag indicating whether or not an instance was
    ///         deployed by this factory.
    /// @param _instance The instance to check.
    /// @return The flag indicating whether or not the instance was deployed by
    ///         this factory.
    function isInstance(address _instance) external view returns (bool);

    /// @notice Gets the number of deployer coordinators registered in this
    ///         factory.
    /// @return The number of deployer coordinators deployed by this factory.
    function getNumberOfDeployerCoordinators() external view returns (uint256);

    /// @notice Gets the deployer coordinator at the specified index.
    /// @param _index The index of the deployer coordinator to get.
    /// @return The deployer coordinator at the specified index.
    function getDeployerCoordinatorAtIndex(
        uint256 _index
    ) external view returns (address);

    /// @notice Returns the deployer coordinators with an index between the
    ///         starting and ending indexes (inclusive).
    /// @param _startIndex The starting index (inclusive).
    /// @param _endIndex The ending index (inclusive).
    /// @return range The deployer coordinators within the specified range.
    function getDeployerCoordinatorsInRange(
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (address[] memory range);

    /// @notice Returns a flag indicating whether or not a deployer coordinator
    ///         is registered in this factory.
    /// @param _deployerCoordinator The deployer coordinator to check.
    /// @return The flag indicating whether or not a deployer coordinator
    ///         is registered in this factory.
    function isDeployerCoordinator(
        address _deployerCoordinator
    ) external view returns (bool);

    /// @notice Gets the deployer coordinators that deployed a list of instances.
    /// @param __instances The instances.
    /// @return coordinators The deployer coordinators.
    function getDeployerCoordinatorByInstances(
        address[] calldata __instances
    ) external view returns (address[] memory coordinators);
}
