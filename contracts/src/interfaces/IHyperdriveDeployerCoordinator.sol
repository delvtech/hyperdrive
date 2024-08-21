// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IHyperdriveDeployerCoordinator {
    /// Errors ///

    /// @notice Thrown when a token approval fails.
    error ApprovalFailed();

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

    /// @notice Thrown when a user attempts to initialize a hyperdrive contract
    ///         before is has been deployed.
    error HyperdriveIsNotDeployed();

    /// @notice Thrown when a deployer provides an insufficient amount of base
    ///         to initialize a payable Hyperdrive instance.
    error InsufficientValue();

    /// @notice Thrown when the base token isn't valid. Each instance will have
    ///         different criteria for what constitutes a valid base token.
    error InvalidBaseToken();

    /// @notice Thrown when the vault shares token isn't valid. Each instance
    ///         will have different criteria for what constitutes a valid base
    ///         token.
    error InvalidVaultSharesToken();

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

    /// @notice Thrown when ether is sent to an instance that doesn't accept
    ///         ether as a deposit asset.
    error NotPayable();

    /// @notice Thrown when the sender of a `deploy`, `deployTarget`, or
    ///         `initialize` transaction isn't the associated factory.
    error SenderIsNotFactory();

    /// @notice Thrown when a user attempts to deploy a target contract after
    ///         it has already been deployed.
    error TargetAlreadyDeployed();

    /// @notice Thrown when an ether transfer fails.
    error TransferFailed();

    /// Functions ///

    /// @notice Returns the deployer coordinator's name.
    /// @return The deployer coordinator's name.
    function name() external view returns (string memory);

    /// @notice Returns the deployer coordinator's kind.
    /// @return The deployer coordinator's kind.
    function kind() external pure returns (string memory);

    /// @notice Returns the deployer coordinator's version.
    /// @return The deployer coordinator's version.
    function version() external pure returns (string memory);

    /// @notice Deploys a Hyperdrive instance with the given parameters.
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

    /// @notice Initializes a pool that was deployed by this coordinator.
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
    ) external payable returns (uint256 lpShares);

    /// @notice Gets the number of targets that need to be deployed for a full
    ///         deployment.
    /// @return numTargets The number of targets that need to be deployed for a
    ///         full deployment.
    function getNumberOfTargets() external pure returns (uint256 numTargets);
}
