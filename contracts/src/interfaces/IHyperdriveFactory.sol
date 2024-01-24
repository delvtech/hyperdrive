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

    event DeployerCoordinatorAdded(address deployerCoordinator);

    event DeployerCoordinatorRemoved(address deployerCoordinator);

    event DefaultPausersUpdated(address[] newDefaultPausers);

    event FeeCollectorUpdated(address newFeeCollector);

    event GovernanceUpdated(address governance);

    event HyperdriveGovernanceUpdated(address hyperdriveGovernance);

    event ImplementationUpdated(address newDeployer);

    event LinkerFactoryUpdated(address newLinkerFactory);

    event LinkerCodeHashUpdated(bytes32 newLinkerCodeHash);

    event CheckpointDurationResolutionUpdated(
        uint256 newCheckpointDurationResolution
    );

    event MaxCheckpointDurationUpdated(uint256 newMaxCheckpointDuration);

    event MinCheckpointDurationUpdated(uint256 newMinCheckpointDuration);

    event MaxPositionDurationUpdated(uint256 newMaxPositionDuration);

    event MinPositionDurationUpdated(uint256 newMinPositionDuration);

    event MaxFeesUpdated(IHyperdrive.Fees newMaxFees);

    event MinFeesUpdated(IHyperdrive.Fees newMinFees);

    /// Errors ///

    error DeployerCoordinatorAlreadyAdded();

    error DeployerCoordinatorNotAdded();

    error DeployerCoordinatorIndexMismatch();

    error InvalidCheckpointDuration();

    error InvalidCheckpointDurationResolution();

    error InvalidDeployConfig();

    error InvalidDeployerCoordinator();

    error InvalidFees();

    error InvalidMaxFees();

    error InvalidMinFees();

    error InvalidMaxCheckpointDuration();

    error InvalidMinCheckpointDuration();

    error InvalidMaxPositionDuration();

    error InvalidMinPositionDuration();

    error InvalidPositionDuration();

    error Unauthorized();
}
