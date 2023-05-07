// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { Errors } from "../libraries/Errors.sol";

/// @author DELV
/// @title HyperdriveFactory
/// @notice Deploys hyperdrive instances and initializes them. It also holds a
///         registry of all deployed hyperdrive instances.
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
    address internal hyperdriveGovernance;

    /// @notice Deploys the contract
    /// @param _governance The address which can update this factory.
    /// @param _deployer The contract which holds the bytecode and deploys new versions.
    /// @param _hyperdriveGovernance The address which is set as the governor of hyperdrive
    constructor(
        address _governance,
        IHyperdriveDeployer _deployer,
        address _hyperdriveGovernance
    ) {
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

    // TODO: Consider adding the data provider deployments to the factory so
    //       that (1) we can ensure they are deployed properly and (2) we can
    //       keep track of them.
    //
    /// @notice Deploys a copy of hyperdrive with the given params
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _dataProvider The address of the data provider.
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
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        bytes32[] memory _extraData,
        uint256 _contribution,
        uint256 _apr
    ) external returns (IHyperdrive) {
        // No invalid deployments
        if (_contribution == 0) revert Errors.InvalidContribution();
        // TODO: We should also overwrite the governance fee field.
        //
        // Overwrite the governance field of the config.
        _config.governance = hyperdriveGovernance;
        // First we call the simplified factory
        IHyperdrive hyperdrive = IHyperdrive(
            hyperdriveDeployer.deploy(
                _config,
                _dataProvider,
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

        // Mark as a version
        isOfficial[address(hyperdrive)] = versionCounter;

        return (hyperdrive);
    }
}
