// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IHyperdriveFactory {
    /// Events ///

    event Deployed(
        uint256 indexed version,
        address hyperdrive,
        IHyperdrive.PoolDeployConfig config,
        bytes extraData
    );

    event DeployerCoordinatorAdded(address indexed deployerCoordinator);

    event DeployerCoordinatorRemoved(address indexed deployerCoordinator);

    event DefaultPausersUpdated(address[] newDefaultPausers);

    event FeeCollectorUpdated(address indexed newFeeCollector);

    event GovernanceUpdated(address indexed governance);

    event HyperdriveGovernanceUpdated(address indexed hyperdriveGovernance);

    event ImplementationUpdated(address indexed newDeployer);

    event LinkerFactoryUpdated(address indexed newLinkerFactory);

    event LinkerCodeHashUpdated(bytes32 indexed newLinkerCodeHash);

    event CheckpointDurationResolutionUpdated(
        uint256 newCheckpointDurationResolution
    );

    event MaxCheckpointDurationUpdated(uint256 newMaxCheckpointDuration);

    event MinCheckpointDurationUpdated(uint256 newMinCheckpointDuration);

    event MaxPositionDurationUpdated(uint256 newMaxPositionDuration);

    event MinPositionDurationUpdated(uint256 newMinPositionDuration);

    event MaxFixedAPRUpdated(uint256 newMaxFixedAPR);

    event MinFixedAPRUpdated(uint256 newMinFixedAPR);

    event MaxTimestretchAPRUpdated(uint256 newMaxTimestretchAPR);

    event MinTimestretchAPRUpdated(uint256 newMinTimestretchAPR);

    event MaxFeesUpdated(IHyperdrive.Fees newMaxFees);

    event MinFeesUpdated(IHyperdrive.Fees newMinFees);

    /// Errors ///

    error DeployerCoordinatorAlreadyAdded();

    error DeployerCoordinatorNotAdded();

    error DeployerCoordinatorIndexMismatch();

    error EndIndexTooLarge();

    error InvalidCheckpointDuration();

    error InvalidCheckpointDurationResolution();

    error InvalidDeployConfig();

    error InvalidDeployerCoordinator();

    error InvalidFees();

    error InvalidIndexes();

    error InvalidMaxFees();

    error InvalidMinFees();

    error InvalidMaxCheckpointDuration();

    error InvalidMinCheckpointDuration();

    error InvalidMaxPositionDuration();

    error InvalidMinPositionDuration();

    error InvalidPositionDuration();

    error InvalidMaxFixedAPR();

    error InvalidMinFixedAPR();

    error InvalidFixedAPR();

    error InvalidMaxTimestretchAPR();

    error InvalidMinTimestretchAPR();

    error InvalidTimestretchAPR();

    error TransferFailed();

    error Unauthorized();
}
