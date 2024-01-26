// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveCoreDeployer } from "../interfaces/IHyperdriveCoreDeployer.sol";
import { IDeployerCoordinator } from "../interfaces/IDeployerCoordinator.sol";
import { IHyperdriveTargetDeployer } from "../interfaces/IHyperdriveTargetDeployer.sol";

/// @author DELV
/// @title HyperdriveDeployerCoordinator
/// @notice This Hyperdrive deployer coordinates the process of deploying the
///         Hyperdrive system utilizing several child deployers.
/// @dev We use multiple deployers to avoid the maximum code size.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveDeployerCoordinator is IDeployerCoordinator {
    /// @notice The contract used to deploy new instances of Hyperdrive.
    address public immutable coreDeployer;

    /// @notice The contract used to deploy new instances of HyperdriveTarget0.
    address public immutable target0Deployer;

    /// @notice The contract used to deploy new instances of HyperdriveTarget1.
    address public immutable target1Deployer;

    /// @notice The contract used to deploy new instances of HyperdriveTarget2.
    address public immutable target2Deployer;

    /// @notice The contract used to deploy new instances of HyperdriveTarget3.
    address public immutable target3Deployer;

    /// @notice Instantiates the deployer coordinator.
    /// @param _coreDeployer The core deployer.
    /// @param _target0Deployer The target0 deployer.
    /// @param _target1Deployer The target1 deployer.
    /// @param _target2Deployer The target2 deployer.
    /// @param _target3Deployer The target3 deployer.
    constructor(
        address _coreDeployer,
        address _target0Deployer,
        address _target1Deployer,
        address _target2Deployer,
        address _target3Deployer
    ) {
        coreDeployer = _coreDeployer;
        target0Deployer = _target0Deployer;
        target1Deployer = _target1Deployer;
        target2Deployer = _target2Deployer;
        target3Deployer = _target3Deployer;
    }

    /// @notice Deploys a Hyperdrive instance with the given parameters.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains the pool and sweep targets.
    /// @return The address of the newly deployed ERC4626Hyperdrive Instance.
    function deploy(
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory _extraData
    ) public virtual returns (address) {
        // Convert the deploy config into the pool config and set the initial
        // vault share price.
        IHyperdrive.PoolConfig memory _config = _copyPoolConfig(_deployConfig);
        _config.initialVaultSharePrice = _getInitialVaultSharePrice(_extraData);

        // Deploy the target0 contract.
        address target0 = IHyperdriveTargetDeployer(target0Deployer).deploy(
            _config,
            _extraData
        );
        address target1 = IHyperdriveTargetDeployer(target1Deployer).deploy(
            _config,
            _extraData
        );
        address target2 = IHyperdriveTargetDeployer(target2Deployer).deploy(
            _config,
            _extraData
        );
        address target3 = IHyperdriveTargetDeployer(target3Deployer).deploy(
            _config,
            _extraData
        );

        // Deploy the Hyperdrive instance.
        return
            IHyperdriveCoreDeployer(coreDeployer).deploy(
                _config,
                _extraData,
                target0,
                target1,
                target2,
                target3
            );
    }

    /// @dev Gets the initial vault share price of the Hyperdrive pool.
    /// @param _extraData The extra data passed to the child deployers.
    /// @return The initial vault share price of the Hyperdrive pool.
    function _getInitialVaultSharePrice(
        bytes memory _extraData
    ) internal view virtual returns (uint256);

    /// @notice Copies the deploy config into a pool config.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    /// @return _config The pool configuration of the Hyperdrive pool.
    function _copyPoolConfig(
        IHyperdrive.PoolDeployConfig memory _deployConfig
    ) internal pure returns (IHyperdrive.PoolConfig memory _config) {
        // Copy the `PoolDeployConfig` into a `PoolConfig` struct.
        _config.baseToken = _deployConfig.baseToken;
        _config.linkerFactory = _deployConfig.linkerFactory;
        _config.linkerCodeHash = _deployConfig.linkerCodeHash;
        _config.minimumShareReserves = _deployConfig.minimumShareReserves;
        _config.minimumTransactionAmount = _deployConfig
            .minimumTransactionAmount;
        _config.positionDuration = _deployConfig.positionDuration;
        _config.checkpointDuration = _deployConfig.checkpointDuration;
        _config.timeStretch = _deployConfig.timeStretch;
        _config.governance = _deployConfig.governance;
        _config.feeCollector = _deployConfig.feeCollector;
        _config.fees = _deployConfig.fees;
    }
}
