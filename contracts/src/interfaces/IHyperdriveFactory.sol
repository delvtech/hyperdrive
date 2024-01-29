// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IHyperdriveFactory {
    /// Events ///

    /// @notice Emitted when a Hyperdrive pool is deployed.
    event Deployed(
        address indexed deployerCoordinator,
        address hyperdrive,
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

    /// @notice Emitted when the factory's governance is updated.
    event GovernanceUpdated(address indexed governance);

    /// @notice Emitted when the governance used in new deployments is updated.
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

    /// @notice Thrown the position duration passed to `deployAndInitialize`
    ///         doesn't fall within the range specified by the minimum and
    ///         maximum position durations.
    error InvalidPositionDuration();

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

    /// @notice Thrown when an ether transfer fails.
    error TransferFailed();

    /// @notice Thrown when an unauthorized caller attempts to update one of the
    ///         governance administered parameters.
    error Unauthorized();
}
