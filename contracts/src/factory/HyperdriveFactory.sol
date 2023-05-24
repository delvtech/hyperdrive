// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { HyperdriveDataProvider } from "../HyperdriveDataProvider.sol";
import { Errors } from "../libraries/Errors.sol";

/// @author DELV
/// @title HyperdriveFactory
/// @notice Deploys hyperdrive instances and initializes them. It also holds a
///         registry of all deployed hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveFactory {
    // The address of the hyperdrive deployer of the most recent code.
    IHyperdriveDeployer public hyperdriveDeployer;
    // The address which coordinates upgrades of the official version of the code
    address public governance;
    // A mapping of all previously deployed hyperdrive instances of all versions
    // 0 is un-deployed then increments for increasing versions
    mapping(address => uint256) public isOfficial;
    uint256 public versionCounter;

    // The address which should control hyperdrive instances
    address public hyperdriveGovernance;

    // The address which should receive hyperdriveFees
    address public feeCollector;

    // The fees each contract for this instance will be deployed with
    IHyperdrive.Fees public fees;

    // The default pausers for new the hyperdrive that are deployed
    address[] public defaultPausers;

    /// @notice Deploys the contract
    /// @param _governance The address which can update this factory.
    /// @param _deployer The contract which holds the bytecode and deploys new versions.
    /// @param _hyperdriveGovernance The address which is set as the governor of hyperdrive
    /// @param _feeCollector The address which should be set as the fee collector in new deployments
    /// @param _fees The fees each deployed instance from this contract will have
    /// @param _defaultPausers The default addresses which will be set to have the pauser role
    constructor(
        address _governance,
        IHyperdriveDeployer _deployer,
        address _hyperdriveGovernance,
        address _feeCollector,
        IHyperdrive.Fees memory _fees,
        address[] memory _defaultPausers
    ) {
        governance = _governance;
        hyperdriveDeployer = _deployer;
        versionCounter = 1;
        hyperdriveGovernance = _hyperdriveGovernance;
        feeCollector = _feeCollector;
        fees = _fees;
        defaultPausers = _defaultPausers;
    }

    /// @notice Allows governance to update the deployer contract.
    /// @param newDeployer The new deployment contract.
    function updateImplementation(IHyperdriveDeployer newDeployer) external {
        // Only governance can call this
        if (msg.sender != governance) revert Errors.Unauthorized();
        // Update version and increment the counter
        hyperdriveDeployer = newDeployer;
        versionCounter++;
    }

    /// @notice Allows governance to change the governance address
    /// @param newGovernance The new governor address
    function updateGovernance(address newGovernance) external {
        // Only governance can call this
        if (msg.sender != governance) revert Errors.Unauthorized();
        // Update version and increment the counter
        governance = newGovernance;
    }

    /// @notice Allows governance to change the hyperdrive governance address
    /// @param newGovernance The new governor address
    function updateHyperdriveGovernance(address newGovernance) external {
        // Only governance can call this
        if (msg.sender != governance) revert Errors.Unauthorized();
        // Update hyperdrive governance
        hyperdriveGovernance = newGovernance;
    }

    /// @notice Allows governance to change the fee collector address
    /// @param newFeeCollector The new governor address
    function updateFeeCollector(address newFeeCollector) external {
        // Only governance can call this
        if (msg.sender != governance) revert Errors.Unauthorized();
        // Update fee collector
        feeCollector = newFeeCollector;
    }

    /// @notice Allows governance to change the fee schedule for the newly deployed factories
    /// @param newFees The fees for all newly deployed contracts
    function updateFees(IHyperdrive.Fees calldata newFees) external {
        // Only governance can call this
        if (msg.sender != governance) revert Errors.Unauthorized();
        // Update the fee struct
        fees = newFees;
    }

    /// @notice Allows governance to change the fee collector address
    /// @param newDefaults The new governor address
    function updateDefaultPausers(address[] calldata newDefaults) external {
        // Only governance can call this
        if (msg.sender != governance) revert Errors.Unauthorized();
        // Update the default pausers
        defaultPausers = newDefaults;
    }

    /// @notice Deploys a copy of hyperdrive with the given params
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @param _extraData The extra data is used by some factories
    /// @param _contribution Base token to call init with
    /// @param _apr The apr to call init with
    /// @return The hyperdrive address deployed
    function deployAndInitialize(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        bytes32[] memory _extraData,
        uint256 _contribution,
        uint256 _apr
    ) public virtual returns (IHyperdrive) {
        // No invalid deployments
        if (_contribution == 0) revert Errors.InvalidContribution();
        // Overwrite the governance and fees field of the config.
        _config.feeCollector = feeCollector;
        _config.governance = address(this);
        _config.fees = fees;
        // We deploy a new data provider for this instance
        address dataProvider = deployDataProvider(
            _config,
            _extraData,
            _linkerCodeHash,
            _linkerFactory
        );

        // Then we call the simplified factory
        IHyperdrive hyperdrive = IHyperdrive(
            hyperdriveDeployer.deploy(
                _config,
                dataProvider,
                _linkerCodeHash,
                _linkerFactory,
                _extraData
            )
        );

        // Initialize the Hyperdrive instance.
        _config.baseToken.transferFrom(
            msg.sender,
            address(this),
            _contribution
        );
        _config.baseToken.approve(address(hyperdrive), type(uint256).max);
        hyperdrive.initialize(_contribution, _apr, msg.sender, true);

        // Setup the pausers roles from the default array
        for (uint256 i = 0; i < defaultPausers.length; ) {
            hyperdrive.setPauser(defaultPausers[i], true);

            unchecked {
                ++i;
            }
        }
        // Reset governance to be the default one
        hyperdrive.setGovernance(hyperdriveGovernance);

        // Mark as a version
        isOfficial[address(hyperdrive)] = versionCounter;

        return (hyperdrive);
    }

    /// @notice This should deploy a data provider which matches the type of the hyperdrives
    ///         this contract will deploy
    /// @param _config The configuration of the pool we are deploying
    /// @param _extraData The extra data from the pool deployment
    /// @param _linkerCodeHash The code hash from the multitoken deployer
    /// @param _linkerFactory The factory of the multitoken deployer
    function deployDataProvider(
        IHyperdrive.PoolConfig memory _config,
        bytes32[] memory _extraData,
        bytes32 _linkerCodeHash,
        address _linkerFactory
    ) internal virtual returns (address);
}
