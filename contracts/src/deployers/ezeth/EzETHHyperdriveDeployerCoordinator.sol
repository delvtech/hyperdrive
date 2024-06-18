// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../interfaces/IHyperdriveDeployerCoordinator.sol";
import { IRestakeManager, IRenzoOracle } from "../../interfaces/IRenzo.sol";
import { ETH, EZETH_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND } from "../../libraries/Constants.sol";
import { FixedPointMath, ONE } from "../../libraries/FixedPointMath.sol";
import { HyperdriveDeployerCoordinator } from "../HyperdriveDeployerCoordinator.sol";

/// @author DELV
/// @title EzETHHyperdriveDeployerCoordinator
/// @custom:disclaimer The language used in this code is for coding convenience
/// @notice The deployer coordinator for the EzETHHyperdrive implementation.
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EzETHHyperdriveDeployerCoordinator is HyperdriveDeployerCoordinator {
    using SafeERC20 for ERC20;
    using FixedPointMath for uint256;

    /// @notice The deployer coordinator's kind.
    string public constant override kind =
        EZETH_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND;

    /// @notice The Renzo contract.
    IRestakeManager public immutable restakeManager;

    /// @notice The RenzoOracle contract.
    IRenzoOracle public immutable renzoOracle;

    /// @notice The ezETH token contract.
    IERC20 public immutable ezETH;

    /// @notice Instantiates the deployer coordinator.
    /// @param _name The deployer coordinator's name.
    /// @param _factory The factory that this deployer will be registered with.
    /// @param _coreDeployer The core deployer.
    /// @param _target0Deployer The target0 deployer.
    /// @param _target1Deployer The target1 deployer.
    /// @param _target2Deployer The target2 deployer.
    /// @param _target3Deployer The target3 deployer.
    /// @param _restakeManager The Renzo contract.
    constructor(
        string memory _name,
        address _factory,
        address _coreDeployer,
        address _target0Deployer,
        address _target1Deployer,
        address _target2Deployer,
        address _target3Deployer,
        IRestakeManager _restakeManager
    )
        HyperdriveDeployerCoordinator(
            _name,
            _factory,
            _coreDeployer,
            _target0Deployer,
            _target1Deployer,
            _target2Deployer,
            _target3Deployer
        )
    {
        restakeManager = _restakeManager;
        ezETH = IERC20(_restakeManager.ezETH());
        renzoOracle = IRenzoOracle(restakeManager.renzoOracle());
    }

    /// @dev Prepares the coordinator for initialization by drawing funds from
    ///      the LP, if necessary.
    /// @param _hyperdrive The Hyperdrive instance that is being initialized.
    /// @param _lp The LP that is initializing the pool.
    /// @param _contribution The amount of capital to supply. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _options The options that configure how the initialization is
    ///        settled.
    /// @return The value that should be sent in the initialize transaction.
    function _prepareInitialize(
        IHyperdrive _hyperdrive,
        address _lp,
        uint256 _contribution,
        IHyperdrive.Options memory _options
    ) internal override returns (uint256) {
        // Depositing as base is disallowed.
        if (_options.asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Otherwise, transfer vault shares from the LP and approve the
        // Hyperdrive pool.
        ERC20(address(ezETH)).safeTransferFrom(
            _lp,
            address(this),
            _contribution
        );
        ERC20(address(ezETH)).forceApprove(address(_hyperdrive), _contribution);

        // NOTE: Return zero since this yield source isn't payable.
        return 0;
    }

    /// @dev We override the message value check since this integration is not
    ///      payable.
    function _checkMessageValue() internal view override {
        if (msg.value != 0) {
            revert IHyperdrive.NotPayable();
        }
    }

    /// @notice Checks the pool configuration to ensure that it is valid.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    function _checkPoolConfig(
        IHyperdrive.PoolDeployConfig memory _deployConfig
    ) internal view override {
        // Perform the default checks.
        super._checkPoolConfig(_deployConfig);

        // Ensure that the base token address is properly configured.
        if (address(_deployConfig.baseToken) != ETH) {
            revert IHyperdriveDeployerCoordinator.InvalidBaseToken();
        }

        // Ensure that the vault shares token address is properly configured.
        if (address(_deployConfig.vaultSharesToken) != address(ezETH)) {
            revert IHyperdriveDeployerCoordinator.InvalidVaultSharesToken();
        }

        // Ensure that the minimum share reserves are equal to 1e15. This value
        // has been tested to prevent arithmetic overflows in the
        // `_updateLiquidity` function when the share reserves are as high as
        // 200 million.
        if (_deployConfig.minimumShareReserves != 1e15) {
            revert IHyperdriveDeployerCoordinator.InvalidMinimumShareReserves();
        }

        // Ensure that the minimum transaction amount are equal to 1e15. This
        // value has been tested to prevent precision issues.
        if (_deployConfig.minimumTransactionAmount != 1e15) {
            revert IHyperdriveDeployerCoordinator
                .InvalidMinimumTransactionAmount();
        }
    }

    /// @dev Gets the initial vault share price of the Hyperdrive pool.
    /// @return The initial vault share price of the Hyperdrive pool.
    function _getInitialVaultSharePrice(
        IHyperdrive.PoolDeployConfig memory, // unused pool deploy config
        bytes memory // unused extra data
    ) internal view override returns (uint256) {
        // Get the total TVL priced in ETH from restakeManager
        (, , uint256 totalTVL) = restakeManager.calculateTVLs();

        // Get the total supply of the ezETH token
        uint256 totalSupply = ezETH.totalSupply();

        return renzoOracle.calculateRedeemAmount(ONE, totalSupply, totalTVL);
    }
}
