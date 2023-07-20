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

    // The address of the hyperdrive deployer of the most recent code.
    IHyperdriveDeployer public hyperdriveDeployer;

    // A mapping of all previously deployed hyperdrive instances of all versions
    // 0 is un-deployed then increments for increasing versions
    mapping(address instance => uint256 version) public isOfficial;
    uint256 public versionCounter;

    // The linker factory which is used to deploy the ERC20 linker contracts.
    address public linkerFactory;

    // The hash of the ERC20 linker contract's constructor code.
    bytes32 public linkerCodeHash;

    // The default fee parameters.
    IHyperdrive.Fees public fees;

    // The address that can update the factory's configuration.
    address public governance;

    // The hyperdrive governance address for new deployments.
    address public hyperdriveGovernance;

    // The address which collects governance fees in new deployments.
    address public feeCollector;

    // The addresses that will be set as the initial pausers in new deployments.
    address[] public defaultPausers;

    // The maximum curve fee that can be used as a factory default.
    uint256 internal immutable maxCurveFee;

    // The maximum flat fee that can be used as a factory default.
    uint256 internal immutable maxFlatFee;

    // The maximum governance fee that can be used as a factory default.
    uint256 internal immutable maxGovernanceFee;

    struct FactoryConfig {
        /// @dev The address which can update a factory.
        address governance;
        /// @dev The address which is set as the governor of hyperdrive.
        address hyperdriveGovernance;
        /// @dev The address which should be set as the fee collector in new deployments.
        address feeCollector;
        /// @dev The fees each deployed instance will have.
        IHyperdrive.Fees fees;
        /// @dev The maximum values that governance can use when updating the default fees.
        IHyperdrive.Fees maxFees;
        /// @dev The default addresses which will be set to have the pauser role.
        address[] defaultPausers;
    }

    // An event that is emitted when a new Hyperdrive instance is deployed.
    event Deployed(
        uint256 indexed version,
        address hyperdrive,
        IHyperdrive.PoolConfig config,
        address linkerFactory,
        bytes32 linkerCodeHash,
        bytes32[] extraData
    );

    /// @notice Deploys the contract.
    /// @param _factoryConfig Configuration of the Hyperdrive Factory.
    /// @param _deployer The contract which holds the bytecode and deploys new versions.
    /// @param _linkerFactory The address of the linker factory.
    /// @param _linkerCodeHash The hash of the linker contract's constructor code.
    constructor(
        FactoryConfig memory _factoryConfig,
        IHyperdriveDeployer _deployer,
        address _linkerFactory,
        bytes32 _linkerCodeHash
    ) {
        // Initialize fee parameters to ensure that max fees are less than
        // 100% and that the initial fee configuration satisfies the max fee
        // constraint.
        maxCurveFee = _factoryConfig.maxFees.curve;
        maxFlatFee = _factoryConfig.maxFees.flat;
        maxGovernanceFee = _factoryConfig.maxFees.governance;
        if (
            maxCurveFee > FixedPointMath.ONE_18 ||
            maxFlatFee > FixedPointMath.ONE_18 ||
            maxGovernanceFee > FixedPointMath.ONE_18
        ) {
            revert IHyperdrive.MaxFeeTooHigh();
        }
        if (
            _factoryConfig.fees.curve > maxCurveFee ||
            _factoryConfig.fees.flat > maxFlatFee ||
            _factoryConfig.fees.governance > maxGovernanceFee
        ) {
            revert IHyperdrive.FeeTooHigh();
        }
        fees = _factoryConfig.fees;

        // Initialize the other parameters.
        governance = _factoryConfig.governance;
        hyperdriveGovernance = _factoryConfig.hyperdriveGovernance;
        feeCollector = _factoryConfig.feeCollector;
        defaultPausers = _factoryConfig.defaultPausers;
        versionCounter = 1;
        hyperdriveDeployer = _deployer;
        linkerFactory = _linkerFactory;
        linkerCodeHash = _linkerCodeHash;
    }

    modifier onlyGovernance() {
        // Only governance can call this
        if (msg.sender != governance) revert IHyperdrive.Unauthorized();
        _;
    }

    event ImplementationUpdated(address indexed newDeployer);

    /// @notice Allows governance to update the deployer contract.
    /// @param newDeployer The new deployment contract.
    function updateImplementation(
        IHyperdriveDeployer newDeployer
    ) external onlyGovernance {
        require(address(newDeployer) != address(0));
        // Update version and increment the counter
        hyperdriveDeployer = newDeployer;
        versionCounter++;

        emit ImplementationUpdated(address(newDeployer));
    }

    event GovernanceUpdated(address indexed newGovernance);

    /// @notice Allows governance to change the governance address
    /// @param newGovernance The new governor address
    function updateGovernance(address newGovernance) external onlyGovernance {
        require(newGovernance != address(0));
        // Update governance
        governance = newGovernance;

        emit GovernanceUpdated(newGovernance);
    }

    event HyperdriveGovernanceUpdated(address indexed newGovernance);

    /// @notice Allows governance to change the hyperdrive governance address
    /// @param newGovernance The new governor address
    function updateHyperdriveGovernance(
        address newGovernance
    ) external onlyGovernance {
        require(newGovernance != address(0));
        // Update hyperdrive governance
        hyperdriveGovernance = newGovernance;

        emit HyperdriveGovernanceUpdated(newGovernance);
    }

    event LinkerFactoryUpdated(address indexed newLinkerFactory);

    /// @notice Allows governance to change the linker factory.
    /// @param newLinkerFactory The new linker code hash.
    function updateLinkerFactory(
        address newLinkerFactory
    ) external onlyGovernance {
        require(newLinkerFactory != address(0));
        // Update the linker factory
        linkerFactory = newLinkerFactory;

        emit LinkerFactoryUpdated(newLinkerFactory);
    }

    event LinkerCodeHashUpdated(bytes32 indexed newCodeHash);

    /// @notice Allows governance to change the linker code hash. This allows
    ///         governance to update the implementation of the ERC20Forwarder.
    /// @param newLinkerCodeHash The new linker code hash.
    function updateLinkerCodeHash(
        bytes32 newLinkerCodeHash
    ) external onlyGovernance {
        // Update the linker code hash
        linkerCodeHash = newLinkerCodeHash;

        emit LinkerCodeHashUpdated(newLinkerCodeHash);
    }

    event FeeCollectorUpdated(address indexed newFeeCollector);

    /// @notice Allows governance to change the fee collector address
    /// @param newFeeCollector The new governor address
    function updateFeeCollector(
        address newFeeCollector
    ) external onlyGovernance {
        require(newFeeCollector != address(0));
        // Update fee collector
        feeCollector = newFeeCollector;

        emit FeeCollectorUpdated(newFeeCollector);
    }

    /// @notice Allows governance to change the fee schedule for the newly deployed factories
    /// @param newFees The fees for all newly deployed contracts
    function updateFees(
        IHyperdrive.Fees calldata newFees
    ) external onlyGovernance {
        if (
            newFees.curve > maxCurveFee ||
            newFees.flat > maxFlatFee ||
            newFees.governance > maxGovernanceFee
        ) {
            revert IHyperdrive.FeeTooHigh();
        }
        // Update the fee struct
        fees = newFees;
    }

    /// @notice Allows governance to change the fee collector address
    /// @param newDefaults The new governor address
    function updateDefaultPausers(
        address[] calldata newDefaults
    ) external onlyGovernance {
        require(newDefaults.length != 0);
        // Update the default pausers
        defaultPausers = newDefaults;
    }

    /// @notice Deploys a copy of hyperdrive with the given params
    /// @dev Function is declared payable to allow payable overrides
    ///     for accepting Ether on initialization, but not supported
    ///     by default within this instance.
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
        // Overwrite the governance and fees field of the config.
        _config.feeCollector = feeCollector;
        _config.governance = address(this);
        _config.fees = fees;

        // We deploy a new data provider for this instance
        address dataProvider = deployDataProvider(
            _config,
            _extraData,
            linkerCodeHash,
            linkerFactory
        );

        // Then we call the simplified factory
        IHyperdrive hyperdrive = IHyperdrive(
            hyperdriveDeployer.deploy(
                _config,
                dataProvider,
                linkerCodeHash,
                linkerFactory,
                _extraData
            )
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

        // Setup the pausers roles from the default array
        for (uint256 i = 0; i < defaultPausers.length; i++) {
            hyperdrive.setPauser(defaultPausers[i], true);
        }
        // Reset governance to be the default one
        hyperdrive.setGovernance(hyperdriveGovernance);

        // Mark as a version
        isOfficial[address(hyperdrive)] = versionCounter;

        // Emit a deployed event.
        _config.governance = hyperdriveGovernance;
        emit Deployed(
            versionCounter,
            address(hyperdrive),
            _config,
            linkerFactory,
            linkerCodeHash,
            _extraData
        );

        return hyperdrive;
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
