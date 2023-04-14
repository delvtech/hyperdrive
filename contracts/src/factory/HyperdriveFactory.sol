// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../interfaces/IHyperdriveDeployer.sol";
import "../libraries/Errors.sol";

/// @author DELV
/// @title HyperdriveFactory
/// @notice Deploys hyperdrive instances and initializes them. It also holds a registry of
///                all deployed hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveFactory {

    // The address of the hyperdrive deployer of the most recent code.
    IHyperdriveDeployer public hyperdriveDeployer;
    // The address which coordinates upgrades of the official version of the code
    address public governance;
    // A mapping of all previously deployed hyperdrive instances of all versions
    // 0 is un-deployed then increments for increasing versions
    mapping(address => uint256) public isOfficial;
    uint256 public versionCounter;

    // The address which should control hyperdrive instances
    address hyperdriveGovernance;

    /// @notice Deploys the contract
    /// @param _governance The address which can update this factory.
    /// @param _deployer The contract which holds the bytecode and deploys new versions.
    /// @param _hyperdriveGovernance The address which is set as the governor of hyperdrive
    constructor(address _governance, IHyperdriveDeployer _deployer, address _hyperdriveGovernance) {
        governance = _governance;
        hyperdriveDeployer = _deployer;
        versionCounter = 1;
        hyperdriveGovernance = _hyperdriveGovernance;
    }


    /// @notice Allows governance to deploy new versions
    /// @param newDeployer The new deployment contract
    function updateImplementation(IHyperdriveDeployer newDeployer) external {
        // Only governance can call this
        if (msg.sender != governance) revert Errors.Unauthorized();
        // Update version and increment the counter
        hyperdriveDeployer = newDeployer;
        versionCounter++;
    }

    /// @notice Allows governance to change
    /// @param newGovernance The new governor address
    function updateGovernance(address newGovernance) external {
        // Only governance can call this
        if (msg.sender != governance) revert Errors.Unauthorized();
        // Update version and increment the counter
        governance = newGovernance;
    }

    /// @notice Deploys a copy of hyperdrive with the given params
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @param _baseToken The base token contract.
    /// @param _initialSharePrice The initial share price.
    /// @param _checkpointsPerTerm The number of checkpoints that elapses before
    ///        bonds can be redeemed one-to-one for base.
    /// @param _checkpointDuration The time in seconds between share price
    ///        checkpoints. Position duration must be a multiple of checkpoint
    ///        duration.
    /// @param _timeStretch The time stretch of the pool.
    /// @param _fees The fees to apply to trades.
    /// @param _contribution Base token to call init with
    /// @param _apr The apr to call init with
    /// @return The hyperdrive address deployed
    function deployAndImplement(
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _baseToken,
        uint256 _initialSharePrice,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        IHyperdrive.Fees memory _fees,
        uint256 _contribution,
        uint256 _apr
    ) external returns(IHyperdrive) {
        // First we call the simplified factory
        IHyperdrive hyperdrive = IHyperdrive(hyperdriveDeployer.deploy(
            _linkerCodeHash,
            _linkerFactory,
            _baseToken,
            _initialSharePrice,
            _checkpointsPerTerm,
            _checkpointDuration,
            _timeStretch,
            _fees,
            hyperdriveGovernance
        ));

        // Then start the process to init
        _baseToken.transferFrom(msg.sender, address(this), _contribution);
        _baseToken.approve(address(hyperdrive), type(uint256).max);
        // Initialize
        hyperdrive.initialize(
            _contribution,
            _apr,
            msg.sender,
            true
        );

        // Mark as a version
        isOfficial[address(hyperdrive)] = versionCounter;

        return (hyperdrive);
    }
}