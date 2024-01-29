// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IHyperdriveDeployerCoordinator {
    /// Errors ///

    /// @notice Thrown when a user attempts to deploy target0 the deployment has
    ///         already been created.
    error DeploymentAlreadyExists();

    /// @notice Thrown when a user attempts to deploy a contract that requires
    ///         the deployment to be created and the deployment doesn't exist.
    error DeploymentDoesNotExist();

    /// @notice Thrown when a user attempts to deploy a Hyperdrive entrypoint
    ///         without first deploying the required targets.
    error IncompleteDeployment();

    /// @notice Thrown when a user attempts to deploy a hyperdrive contract
    ///         after it has already been deployed.
    error HyperdriveAlreadyDeployed();

    /// @notice Thrown when the checkpoint duration specified is zero.
    error InvalidCheckpointDuration();

    /// @notice Thrown when the curve fee, flat fee, governance LP fee, or
    ///         governance zombie fee is greater than 100%.
    error InvalidFeeAmounts();

    /// @notice Thrown when the minimum share reserves is too small. The
    ///         absolute smallest allowable minimum share reserves is 1e3;
    ///         however, yield sources may require a larger minimum share
    ///         reserves.
    error InvalidMinimumShareReserves();

    /// @notice Thrown when the minimum transaction amount is too small.
    error InvalidMinimumTransactionAmount();

    /// @notice Thrown when the position duration is smaller than the checkpoint
    ///         duration or is not a multiple of the checkpoint duration.
    error InvalidPositionDuration();

    /// @notice Thrown when a user attempts to deploy a target using a target
    ///         index that is outside of the accepted range.
    error InvalidTargetIndex();

    /// @notice Thrown when a user attempts to deploy a contract in an existing
    ///         deployment with a config that doesn't match the deployment's
    ///         config hash.
    error MismatchedConfig();

    /// @notice Thrown when a user attempts to deploy a contract in an existing
    ///         deployment with extra data that doesn't match the deployment's
    ///         extra data hash.
    error MismatchedExtraData();

    /// @notice Thrown when a user attempts to deploy a target contract after
    ///         it has already been deployed.
    error TargetAlreadyDeployed();

    /// Functions ///

    /// @notice Deploys a Hyperdrive instance with the given parameters.
    /// @param _deploymentId The ID of the deployment.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains the pool and sweep targets.
    /// @param _salt The create2 salt used to deploy Hyperdrive.
    /// @return The address of the newly deployed Hyperdrive instance.
    function deploy(
        bytes32 _deploymentId,
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory _extraData,
        bytes32 _salt
    ) external returns (address);

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
    ) external returns (address);
}
