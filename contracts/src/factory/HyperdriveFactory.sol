// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { FixedPointMath, ONE } from "../libraries/FixedPointMath.sol";

/// @author DELV
/// @title HyperdriveFactory
/// @notice Deploys hyperdrive instances and initializes them. It also holds a
///         registry of all deployed hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveFactory {
    using FixedPointMath for uint256;
    using SafeTransferLib for ERC20;

    /// @notice Emitted when governance is transferred.
    event GovernanceUpdated(address indexed governance);

    /// @notice Emitted when the Hyperdrive implementation is updated.
    event ImplementationUpdated(address indexed newDeployer);

    /// @notice Emitted when the Hyperdrive governance address is updated.
    event HyperdriveGovernanceUpdated(address indexed hyperdriveGovernance);

    /// @notice Emitted when the fee collector is updated.
    event FeeCollectorUpdated(address indexed newFeeCollector);

    /// @notice Emitted when the linker factory is updated.
    event LinkerFactoryUpdated(address indexed newLinkerFactory);

    /// @notice Emitted when the linker code hash is updated.
    event LinkerCodeHashUpdated(bytes32 indexed newLinkerCodeHash);

    /// @notice The event that is emitted when new instances are deployed.
    event Deployed(
        uint256 indexed version,
        address hyperdrive,
        IHyperdrive.PoolDeployConfig config,
        bytes extraData
    );

    /// @notice The governance address that updates the factory's configuration.
    address public governance;

    /// @notice The number of times the factory's deployer has been updated.
    uint256 public versionCounter = 1;

    /// @notice A mapping from deployed Hyperdrive instances to the version
    ///         of the deployer that deployed them.
    mapping(address instance => uint256 version) public isOfficial;

    /// @notice The governance address used when new instances are deployed.
    address public hyperdriveGovernance;

    /// @notice The linker factory used when new instances are deployed.
    address public linkerFactory;

    /// @notice The linker code hash used when new instances are deployed.
    bytes32 public linkerCodeHash;

    /// @notice The fee parameters used when new instances are deployed.
    IHyperdrive.Fees public fees;

    /// @notice The fee collector used when new instances are deployed.
    address public feeCollector;

    /// @dev The maximum curve fee that can be used as a factory default.
    uint256 internal immutable maxCurveFee;

    /// @dev The maximum flat fee that can be used as a factory default.
    uint256 internal immutable maxFlatFee;

    /// @dev The maximum governance LP fee that can be used as a factory default.
    uint256 internal immutable maxGovernanceLPFee;

    /// @dev The maximum governance zombie fee that can be used as a factory default.
    uint256 internal immutable maxGovernanceZombieFee;

    /// @dev The defaultPausers used when new instances are deployed.
    address[] internal _defaultPausers;

    struct FactoryConfig {
        /// @dev The address which can update a factory.
        address governance;
        /// @dev The address which is set as the governor of hyperdrive.
        address hyperdriveGovernance;
        /// @dev The default addresses which will be set to have the pauser role.
        address[] defaultPausers;
        /// @dev The recipient of governance fees from new deployments.
        address feeCollector;
        /// @dev The fees each deployed instance will have.
        IHyperdrive.Fees fees;
        /// @dev The upper bounds on the fee parameters that governance can set.
        IHyperdrive.Fees maxFees;
        /// @dev The address of the linker factory.
        address linkerFactory;
        /// @dev The hash of the linker contract's constructor code.
        bytes32 linkerCodeHash;
    }

    /// @dev List of all hyperdrive deployers onboarded by governance.
    address[] internal _hyperdriveDeployers;

    /// @notice Mapping to check if an hyperdriveDeployer is in the _hyperdriveDeployers array.
    mapping(address => bool) public isHyperdriveDeployer;

    /// @dev Array of all instances deployed by this factory.
    /// @dev Can be manually updated by governance to add previous instances deployed.
    address[] internal _instances;

    /// @dev Mapping to check if an instance is in the _instances array.
    mapping(address => bool) public isInstance;

    /// @notice Initializes the factory.
    /// @param _factoryConfig Configuration of the Hyperdrive Factory.
    constructor(FactoryConfig memory _factoryConfig) {
        // Initialize fee parameters to ensure that max fees are less than
        // 100% and that the initial fee configuration satisfies the max fee
        // constraint.
        maxCurveFee = _factoryConfig.maxFees.curve;
        maxFlatFee = _factoryConfig.maxFees.flat;
        maxGovernanceLPFee = _factoryConfig.maxFees.governanceLP;
        maxGovernanceZombieFee = _factoryConfig.maxFees.governanceZombie;
        if (
            maxCurveFee > ONE ||
            maxFlatFee > ONE ||
            maxGovernanceLPFee > ONE ||
            maxGovernanceZombieFee > ONE
        ) {
            revert IHyperdrive.MaxFeeTooHigh();
        }
        if (
            _factoryConfig.fees.curve > maxCurveFee ||
            _factoryConfig.fees.flat > maxFlatFee ||
            _factoryConfig.fees.governanceLP > maxGovernanceLPFee ||
            _factoryConfig.fees.governanceZombie > maxGovernanceZombieFee
        ) {
            revert IHyperdrive.FeeTooHigh();
        }
        fees = _factoryConfig.fees;

        // Initialize the other parameters.
        governance = _factoryConfig.governance;
        hyperdriveGovernance = _factoryConfig.hyperdriveGovernance;
        feeCollector = _factoryConfig.feeCollector;
        _defaultPausers = _factoryConfig.defaultPausers;
        linkerFactory = _factoryConfig.linkerFactory;
        linkerCodeHash = _factoryConfig.linkerCodeHash;
    }

    /// @dev Ensure that the sender is the governance address.
    modifier onlyGovernance() {
        if (msg.sender != governance) revert IHyperdrive.Unauthorized();
        _;
    }

    /// @notice Allows governance to transfer the governance role.
    /// @param _governance The new governance address.
    function updateGovernance(address _governance) external onlyGovernance {
        governance = _governance;
        emit GovernanceUpdated(_governance);
    }

    /// @notice Allows governance to change the hyperdrive governance address
    /// @param _hyperdriveGovernance The new hyperdrive governance address.
    function updateHyperdriveGovernance(
        address _hyperdriveGovernance
    ) external onlyGovernance {
        hyperdriveGovernance = _hyperdriveGovernance;
        emit HyperdriveGovernanceUpdated(_hyperdriveGovernance);
    }

    /// @notice Allows governance to change the linker factory.
    /// @param _linkerFactory The new linker factory.
    function updateLinkerFactory(
        address _linkerFactory
    ) external onlyGovernance {
        require(_linkerFactory != address(0));
        linkerFactory = _linkerFactory;
        emit LinkerFactoryUpdated(_linkerFactory);
    }

    /// @notice Allows governance to change the linker code hash. This allows
    ///         governance to update the implementation of the ERC20Forwarder.
    /// @param _linkerCodeHash The new linker code hash.
    function updateLinkerCodeHash(
        bytes32 _linkerCodeHash
    ) external onlyGovernance {
        linkerCodeHash = _linkerCodeHash;
        emit LinkerCodeHashUpdated(_linkerCodeHash);
    }

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
        if (
            _fees.curve > maxCurveFee ||
            _fees.flat > maxFlatFee ||
            _fees.governanceLP > maxGovernanceLPFee ||
            _fees.governanceZombie > maxGovernanceZombieFee
        ) {
            revert IHyperdrive.FeeTooHigh();
        }
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

    /// @notice Allows governance to add a new hyperdrive deployer.
    /// @param _hyperdriveDeployer The new hyperdrive deployer.
    function addHyperdriveDeployer(
        address _hyperdriveDeployer
    ) external onlyGovernance {
        if (isHyperdriveDeployer[_hyperdriveDeployer]) {
            revert IHyperdrive.HyperdriveDeployerAlreadyAdded();
        }
        isHyperdriveDeployer[_hyperdriveDeployer] = true;
        _hyperdriveDeployers.push(_hyperdriveDeployer);
    }

    /// @notice Allows governance to remove an existing hyperdrive deployer.
    /// @param _hyperdriveDeployer The hyperdrive deployer to remove.
    /// @param _index The index of the hyperdrive deployer to remove.
    function removeHyperdriveDeployer(
        address _hyperdriveDeployer,
        uint256 _index
    ) external onlyGovernance {
        if (!isHyperdriveDeployer[_hyperdriveDeployer]) {
            revert IHyperdrive.HyperdriveDeployerNotAdded();
        }
        if (_hyperdriveDeployers[_index] != _hyperdriveDeployer) {
            revert IHyperdrive.HyperdriveDeployerIndexMismatch();
        }
        isHyperdriveDeployer[_hyperdriveDeployer] = false;
        _hyperdriveDeployers[_index] = _hyperdriveDeployers[
            _hyperdriveDeployers.length - 1
        ];
        _hyperdriveDeployers.pop();
    }

    /// @notice Deploys a Hyperdrive instance with the factory's configuration.
    /// @dev This function is declared as payable to allow payable overrides
    ///      to accept ether on initialization, but payability is not supported
    ///      by default.
    /// @param _hyperdriveDeployer Address of the hyperdrive deployer.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains data necessary for the
    ///        specific deployer.
    /// @param _contribution Base token to call init with
    /// @param _apr The apr to call init with
    /// @param _initializeExtraData The extra data for the `initialize` call.
    /// @return The hyperdrive address deployed.
    function deployAndInitialize(
        address _hyperdriveDeployer,
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory _extraData,
        uint256 _contribution,
        uint256 _apr,
        bytes memory _initializeExtraData
    ) public payable virtual returns (IHyperdrive) {
        // Ensure that the target deployer has been registered.
        if (!isHyperdriveDeployer[_hyperdriveDeployer]) {
            revert IHyperdrive.InvalidDeployer();
        }

        // Deploy the data provider and the instance with the factory's
        // configuration. Add this instance to the registry and emit an event
        // with the deployment configuration. The factory assumes the governance
        // role during deployment so that it can set up some initial values;
        // however the governance role will ultimately be transferred to the
        // hyperdrive governance address.
        _deployConfig.linkerFactory = linkerFactory;
        _deployConfig.linkerCodeHash = linkerCodeHash;
        _deployConfig.feeCollector = feeCollector;
        _deployConfig.governance = address(this);
        _deployConfig.fees = fees;
        IHyperdrive hyperdrive = IHyperdrive(
            IHyperdriveDeployer(_hyperdriveDeployer).deploy(
                _deployConfig,
                _extraData
            )
        );
        isOfficial[address(hyperdrive)] = versionCounter;
        _deployConfig.governance = hyperdriveGovernance;
        emit Deployed(
            versionCounter,
            address(hyperdrive),
            _deployConfig,
            _extraData
        );

        // Add the newly deployed Hyperdrive instance to the registry.
        _instances.push(address(hyperdrive));
        isInstance[address(hyperdrive)] = true;

        // Initialize the Hyperdrive instance.
        uint256 refund;
        if (msg.value >= _contribution) {
            // Only the contribution amount of ether will be passed to
            // Hyperdrive.
            refund = msg.value - _contribution;

            // Initialize the Hyperdrive instance.
            hyperdrive.initialize{ value: _contribution }(
                _contribution,
                _apr,
                IHyperdrive.Options({
                    destination: msg.sender,
                    asBase: true,
                    extraData: _initializeExtraData
                })
            );
        } else {
            // None of the provided ether is used for the contribution.
            refund = msg.value;

            // Transfer the contribution to this contract and set an approval
            // on Hyperdrive to prepare for initialization.
            ERC20(address(_deployConfig.baseToken)).safeTransferFrom(
                msg.sender,
                address(this),
                _contribution
            );
            ERC20(address(_deployConfig.baseToken)).safeApprove(
                address(hyperdrive),
                _contribution
            );

            // Initialize the Hyperdrive instance.
            hyperdrive.initialize(
                _contribution,
                _apr,
                IHyperdrive.Options({
                    destination: msg.sender,
                    asBase: true,
                    extraData: _initializeExtraData
                })
            );
        }

        // Refund any excess ether that was sent to this contract.
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }

        // Set the default pausers and transfer the governance status to the
        // hyperdrive governance address.
        for (uint256 i = 0; i < _defaultPausers.length; ) {
            hyperdrive.setPauser(_defaultPausers[i], true);
            unchecked {
                ++i;
            }
        }
        hyperdrive.setGovernance(hyperdriveGovernance);

        return hyperdrive;
    }

    /// @notice Gets the default pausers.
    /// @return The default pausers.
    function getDefaultPausers() external view returns (address[] memory) {
        return _defaultPausers;
    }

    /// @notice Gets the number of instances deployed by this factory.
    /// @return The number of instances deployed by this factory.
    function getNumberOfInstances() external view returns (uint256) {
        return _instances.length;
    }

    /// @notice Gets the instance at the specified index.
    /// @param index The index of the instance to get.
    /// @return The instance at the specified index.
    function getInstanceAtIndex(uint256 index) external view returns (address) {
        return _instances[index];
    }

    /// @notice Returns the _instances array according to specified indices.
    /// @param startIndex The starting index of the instances to get.
    /// @param endIndex The ending index of the instances to get.
    /// @return range The resulting custom portion of the _instances array.
    function getInstancesInRange(
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (address[] memory range) {
        // If the indexes are malformed, revert.
        if (startIndex > endIndex) {
            revert IHyperdrive.InvalidIndexes();
        }
        if (endIndex > _instances.length) {
            revert IHyperdrive.EndIndexTooLarge();
        }

        // Return the range of instances.
        range = new address[](endIndex - startIndex + 1);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            range[i - startIndex] = _instances[i];
        }
    }

    /// @notice Gets the number of hyperdrive deployers deployed by this factory.
    /// @return The number of hyperdrive deployers deployed by this factory.
    function getNumberOfHyperdriveDeployers() external view returns (uint256) {
        return _hyperdriveDeployers.length;
    }

    /// @notice Gets the instance at the specified index.
    /// @param index The index of the instance to get.
    /// @return The instance at the specified index.
    function getHyperdriveDeployerAtIndex(
        uint256 index
    ) external view returns (address) {
        return _hyperdriveDeployers[index];
    }

    /// @notice Returns the hyperdrive deployers array according to specified indices.
    /// @param startIndex The starting index of the hyperdrive deployers to get.
    /// @param endIndex The ending index of the hyperdrive deployers to get.
    /// @return range The resulting custom portion of the hyperdrive deployers array.
    function getHyperdriveDeployersInRange(
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (address[] memory range) {
        // If the indexes are malformed, revert.
        if (startIndex > endIndex) {
            revert IHyperdrive.InvalidIndexes();
        }
        if (endIndex > _hyperdriveDeployers.length) {
            revert IHyperdrive.EndIndexTooLarge();
        }

        // Return the range of instances.
        range = new address[](endIndex - startIndex + 1);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            range[i - startIndex] = _hyperdriveDeployers[i];
        }
    }
}
