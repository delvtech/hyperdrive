// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveDataProvider } from "../HyperdriveDataProvider.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";

/// @author DELV
/// @title HyperdriveFactory
/// @notice Deploys hyperdrive instances and initializes them. It also holds a
///         registry of all deployed hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveFactory {
    using FixedPointMath for uint256;

    /// @notice The governance address that updates the factory's configuration.
    address public governance;

    /// @notice The number of times the factory's deployer has been updated.
    uint256 public versionCounter;

    /// @notice A mapping from deployed Hyperdrive instances to the version
    ///         of the deployer that deployed them.
    mapping(address instance => uint256 version) public isOfficial;

    /// @notice The contract used to deploy new instances.
    IHyperdriveDeployer public hyperdriveDeployer;

    /// @notice The governance address used when new instances are deployed.
    address public hyperdriveGovernance;

    /// @notice The linker factory used when new instances are deployed.
    address public linkerFactory;

    /// @notice The linker code hash used when new instances are deployed.
    bytes32 public linkerCodeHash;

    /// @notice The fee collector used when new instances are deployed.
    address public feeCollector;

    /// @notice The fee parameters used when new instances are deployed.
    IHyperdrive.Fees public fees;

    /// @dev The defaultPausers used when new instances are deployed.
    address[] internal _defaultPausers;

    /// @notice The event that is emitted when new instances are deployed.
    event Deployed(
        uint256 indexed version,
        address hyperdrive,
        IHyperdrive.PoolConfig config,
        address linkerFactory,
        bytes32 linkerCodeHash,
        bytes32[] extraData
    );

    /// @notice Initializes the factory.
    /// @param _governance The address that can update the factory's configuration.
    /// @param _deployer The contract that deploys new hyperdrive instances.
    /// @param _hyperdriveGovernance The governance address for Hyperdrive pools.
    /// @param _feeCollector The fee collector address.
    /// @param _fees The fee parameters.
    /// @param _defaultPausers_ The default pausers.
    /// @param _linkerFactory The linker factory.
    /// @param _linkerCodeHash The hash of the linker contract's constructor code.
    constructor(
        address _governance,
        IHyperdriveDeployer _deployer,
        address _hyperdriveGovernance,
        address _feeCollector,
        IHyperdrive.Fees memory _fees,
        address[] memory _defaultPausers_,
        address _linkerFactory,
        bytes32 _linkerCodeHash
    ) {
        governance = _governance;
        hyperdriveDeployer = _deployer;
        versionCounter = 1;
        hyperdriveGovernance = _hyperdriveGovernance;
        feeCollector = _feeCollector;
        fees = _fees;
        _defaultPausers = _defaultPausers_;
        linkerFactory = _linkerFactory;
        linkerCodeHash = _linkerCodeHash;
    }

    /// @dev Ensure that the sender is the governance address.
    modifier onlyGovernance() {
        if (msg.sender != governance) revert IHyperdrive.Unauthorized();
        _;
    }

    event ImplementationUpdated(address indexed newDeployer);

    /// @notice Allows governance to update the deployer contract.
    /// @param newDeployer The new deployment contract.
    function updateImplementation(
        IHyperdriveDeployer newDeployer
    ) external onlyGovernance {
        // Update the deployer.
        require(address(newDeployer) != address(0));
        hyperdriveDeployer = newDeployer;

        // Increment the version number.
        versionCounter++;

        emit ImplementationUpdated(address(newDeployer));
    }

    event GovernanceUpdated(address indexed governance);

    /// @notice Allows governance to transfer the governance role.
    /// @param _governance The new governance address.
    function updateGovernance(address _governance) external onlyGovernance {
        governance = _governance;
        emit GovernanceUpdated(_governance);
    }

    event HyperdriveGovernanceUpdated(address indexed hyperdriveGovernance);

    /// @notice Allows governance to change the hyperdrive governance address
    /// @param _hyperdriveGovernance The new hyperdrive governance address.
    function updateHyperdriveGovernance(
        address _hyperdriveGovernance
    ) external onlyGovernance {
        hyperdriveGovernance = _hyperdriveGovernance;
        emit HyperdriveGovernanceUpdated(_hyperdriveGovernance);
    }

    event LinkerFactoryUpdated(address indexed newLinkerFactory);

    /// @notice Allows governance to change the linker factory.
    /// @param _linkerFactory The new linker factory.
    function updateLinkerFactory(
        address _linkerFactory
    ) external onlyGovernance {
        require(_linkerFactory != address(0));
        linkerFactory = _linkerFactory;
        emit LinkerFactoryUpdated(_linkerFactory);
    }

    event LinkerCodeHashUpdated(bytes32 indexed newCodeHash);

    /// @notice Allows governance to change the linker code hash. This allows
    ///         governance to update the implementation of the ERC20Forwarder.
    /// @param _linkerCodeHash The new linker code hash.
    function updateLinkerCodeHash(
        bytes32 _linkerCodeHash
    ) external onlyGovernance {
        linkerCodeHash = _linkerCodeHash;
        emit LinkerCodeHashUpdated(_linkerCodeHash);
    }

    event FeeCollectorUpdated(address indexed newFeeCollector);

    /// @notice Allows governance to change the fee collector address.
    /// @param _feeCollector The new fee collector address.
    function updateFeeCollector(address _feeCollector) external onlyGovernance {
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(_feeCollector);
    }

    /// @notice Allows governance to update the default fee schedule that will
    ///         be used in new deployments.
    /// @param _fees The new defaults for the fee parameters.
    function updateFees(
        IHyperdrive.Fees calldata _fees
    ) external onlyGovernance {
        fees = _fees;
    }

    /// @notice Allows governance to change the default pausers.
    /// @param _defaultPausers_ The new list of default pausers.
    function updateDefaultPausers(
        address[] calldata _defaultPausers_
    ) external onlyGovernance {
        // Update the list of default pausers.
        _defaultPausers = _defaultPausers_;
    }

    /// @notice Deploys a Hyperdrive instance with the factory's configuration.
    /// @dev This function is declared as payable to allow payable overrides
    ///      to accept ether on initialization, but payability is not supported
    ///      by default.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _extraData The extra data is used by some factories
    /// @param _contribution Base token to call init with
    /// @param _apr The apr to call init with
    /// @return The hyperdrive address deployed
    function deployAndInitialize(
        IHyperdrive.PoolConfig memory _config,
        bytes32[] memory _extraData,
        uint256 _contribution,
        uint256 _apr
    ) public payable virtual returns (IHyperdrive) {
        if (msg.value > 0) {
            revert IHyperdrive.NonPayableInitialization();
        }

        // Deploy the data provider and the instance with the factory's
        // configuration. Add this instance to the registry and emit an event
        // with the deployment configuration. The factory assumes the governance
        // role during deployment so that it can set up some initial values;
        // however the governance role will ultimately be transferred to the
        // hyperdrive governance address.
        _config.feeCollector = feeCollector;
        _config.governance = address(this);
        _config.fees = fees;
        address dataProvider = deployDataProvider(
            _config,
            _extraData,
            linkerCodeHash,
            linkerFactory
        );
        IHyperdrive hyperdrive = IHyperdrive(
            hyperdriveDeployer.deploy(
                _config,
                dataProvider,
                linkerCodeHash,
                linkerFactory,
                _extraData
            )
        );
        isOfficial[address(hyperdrive)] = versionCounter;
        _config.governance = hyperdriveGovernance;
        emit Deployed(
            versionCounter,
            address(hyperdrive),
            _config,
            linkerFactory,
            linkerCodeHash,
            _extraData
        );

        // Initialize the Hyperdrive instance.
        _config.baseToken.transferFrom(
            msg.sender,
            address(this),
            _contribution
        );
        if (
            !_config.baseToken.approve(address(hyperdrive), type(uint256).max)
        ) {
            revert IHyperdrive.ApprovalFailed();
        }
        hyperdrive.initialize(_contribution, _apr, msg.sender, true);

        // Set the default pausers and transfer the governance status to the
        // hyperdrive governance address.
        for (uint256 i = 0; i < _defaultPausers.length; i++) {
            hyperdrive.setPauser(_defaultPausers[i], true);
        }
        hyperdrive.setGovernance(hyperdriveGovernance);

        return hyperdrive;
    }

    // TODO: We should be able to update the data providers bytecode when we
    // up the deployer; however, this change should be made in the context of
    // our mainnet proxy design.
    //
    /// @notice Deploys a Hyperdrive instance with the factory's configuration.
    /// @dev This should be overrided so that the data provider corresponding
    ///      to an individual instance is used.
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

    /// @notice Gets the default pausers.
    /// @return The default pausers.
    function getDefaultPausers() external view returns (address[] memory) {
        return _defaultPausers;
    }
}
