// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { EzETHLineaConversions } from "../../instances/ezeth-linea/EzETHLineaConversions.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../interfaces/IHyperdriveDeployerCoordinator.sol";
import { IXRenzoDeposit } from "../../interfaces/IXRenzoDeposit.sol";
import { ETH, EZETH_LINEA_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND } from "../../libraries/Constants.sol";
import { ONE } from "../../libraries/FixedPointMath.sol";
import { HyperdriveDeployerCoordinator } from "../HyperdriveDeployerCoordinator.sol";

/// @author DELV
/// @title EzETHLineaHyperdriveDeployerCoordinator
/// @notice The deployer coordinator for the EzETHLineaHyperdrive
///         implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EzETHLineaHyperdriveDeployerCoordinator is
    HyperdriveDeployerCoordinator
{
    /// @notice The deployer coordinator's kind.
    string public constant override kind =
        EZETH_LINEA_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND;

    /// @notice The Renzo deposit contract on Linea. The latest mint rate is
    ///         used as the vault share price.
    IXRenzoDeposit public immutable xRenzoDeposit;

    /// @notice Instantiates the deployer coordinator.
    /// @param _name The deployer coordinator's name.
    /// @param _factory The factory that this deployer will be registered with.
    /// @param _coreDeployer The core deployer.
    /// @param _target0Deployer The target0 deployer.
    /// @param _target1Deployer The target1 deployer.
    /// @param _target2Deployer The target2 deployer.
    /// @param _target3Deployer The target3 deployer.
    /// @param _target4Deployer The target4 deployer.
    /// @param _xRenzoDeposit The xRenzoDeposit contract that provides the
    ///        vault share price.
    constructor(
        string memory _name,
        address _factory,
        address _coreDeployer,
        address _target0Deployer,
        address _target1Deployer,
        address _target2Deployer,
        address _target3Deployer,
        address _target4Deployer,
        IXRenzoDeposit _xRenzoDeposit
    )
        HyperdriveDeployerCoordinator(
            _name,
            _factory,
            _coreDeployer,
            _target0Deployer,
            _target1Deployer,
            _target2Deployer,
            _target3Deployer,
            _target4Deployer
        )
    {
        xRenzoDeposit = _xRenzoDeposit;
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
    /// @return value The value that should be sent in the initialize transaction.
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

        // Take custody of the contribution and approve Hyperdrive to pull
        // the tokens.
        IERC20 vaultSharesToken = IERC20(_hyperdrive.vaultSharesToken());
        bool success = vaultSharesToken.transferFrom(
            _lp,
            address(this),
            _contribution
        );
        if (!success) {
            revert IHyperdriveDeployerCoordinator.TransferFailed();
        }
        success = vaultSharesToken.approve(address(_hyperdrive), _contribution);
        if (!success) {
            revert IHyperdriveDeployerCoordinator.ApprovalFailed();
        }

        // NOTE: Return zero since this yield source isn't payable.
        return 0;
    }

    /// @notice Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(uint256 _shareAmount) public view returns (uint256) {
        return EzETHLineaConversions.convertToBase(xRenzoDeposit, _shareAmount);
    }

    /// @notice Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        uint256 _baseAmount
    ) public view returns (uint256) {
        return EzETHLineaConversions.convertToBase(xRenzoDeposit, _baseAmount);
    }

    /// @dev We override the message value check since this integration is
    ///      not payable.
    function _checkMessageValue() internal view override {
        if (msg.value != 0) {
            revert IHyperdrive.NotPayable();
        }
    }

    /// @notice Checks the pool configuration to ensure that it is valid.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    /// @param _extraData The empty extra data.
    function _checkPoolConfig(
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory _extraData
    ) internal view override {
        // Perform the default checks.
        super._checkPoolConfig(_deployConfig, _extraData);

        // Ensure that the vault shares token address is properly configured.
        if (
            address(_deployConfig.vaultSharesToken) !=
            address(xRenzoDeposit.xezETH())
        ) {
            revert IHyperdriveDeployerCoordinator.InvalidVaultSharesToken();
        }

        // Ensure that the base token address is properly configured.
        if (address(_deployConfig.baseToken) != ETH) {
            revert IHyperdriveDeployerCoordinator.InvalidBaseToken();
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
        IHyperdrive.PoolDeployConfig memory, // unused _deployConfig
        bytes memory // unused _extraData
    ) internal view override returns (uint256) {
        return convertToBase(ONE);
    }
}
