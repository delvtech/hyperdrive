// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { RsETHLineaConversions } from "../../instances/rseth-linea/RsETHLineaConversions.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../interfaces/IHyperdriveDeployerCoordinator.sol";
import { IRSETHPoolV2 } from "../../interfaces/IRSETHPoolV2.sol";
import { ETH, RSETH_LINEA_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND } from "../../libraries/Constants.sol";
import { ONE } from "../../libraries/FixedPointMath.sol";
import { HyperdriveDeployerCoordinator } from "../HyperdriveDeployerCoordinator.sol";

/// @author DELV
/// @title RsETHLineaHyperdriveDeployerCoordinator
/// @notice The deployer coordinator for the RsETHLineaHyperdrive
///         implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract RsETHLineaHyperdriveDeployerCoordinator is
    HyperdriveDeployerCoordinator
{
    /// @notice The deployer coordinator's kind.
    string public constant override kind =
        RSETH_LINEA_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND;

    /// @notice The Kelp DAO deposit contract on Linea. The rsETH/ETH price is
    ///         used as the vault share price.
    IRSETHPoolV2 public immutable rsETHPool;

    /// @notice Instantiates the deployer coordinator.
    /// @param _name The deployer coordinator's name.
    /// @param _factory The factory that this deployer will be registered with.
    /// @param _coreDeployer The core deployer.
    /// @param _target0Deployer The target0 deployer.
    /// @param _target1Deployer The target1 deployer.
    /// @param _target2Deployer The target2 deployer.
    /// @param _target3Deployer The target3 deployer.
    /// @param _target4Deployer The target4 deployer.
    /// @param _rsETHPool The Kelp DAO deposit contract that provides the vault
    ///        share price.
    constructor(
        string memory _name,
        address _factory,
        address _coreDeployer,
        address _target0Deployer,
        address _target1Deployer,
        address _target2Deployer,
        address _target3Deployer,
        address _target4Deployer,
        IRSETHPoolV2 _rsETHPool
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
        rsETHPool = _rsETHPool;
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
    ) internal override returns (uint256 value) {
        // Depositing as base is disallowed when deposit fees are enabled..
        if (_options.asBase && rsETHPool.feeBps() > 0) {
            revert IHyperdrive.UnsupportedToken();
        }
        // If base is the deposit asset, ensure that enough ether was sent to
        // the contract and return the amount of ether that should be sent for
        // the contribution.
        else if (_options.asBase) {
            if (msg.value < _contribution) {
                revert IHyperdriveDeployerCoordinator.InsufficientValue();
            }
            value = _contribution;
        }
        // Otherwise, transfer vault shares from the LP and approve the
        // Hyperdrive pool.
        else {
            // NOTE: We don't use `forceApprove` or `safeTransferFrom` since
            // wrsETH is an OpenZeppelin token contract.
            //
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
            success = vaultSharesToken.approve(
                address(_hyperdrive),
                _contribution
            );
            if (!success) {
                revert IHyperdriveDeployerCoordinator.ApprovalFailed();
            }
        }

        return value;
    }

    /// @notice Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(uint256 _shareAmount) public view returns (uint256) {
        return RsETHLineaConversions.convertToBase(rsETHPool, _shareAmount);
    }

    /// @notice Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        uint256 _baseAmount
    ) public view returns (uint256) {
        return RsETHLineaConversions.convertToShares(rsETHPool, _baseAmount);
    }

    /// @dev We override the message value check since this integration is
    ///      payable.
    function _checkMessageValue() internal view override {}

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
        if (address(_deployConfig.vaultSharesToken) != rsETHPool.wrsETH()) {
            revert IHyperdriveDeployerCoordinator.InvalidVaultSharesToken();
        }

        // Ensure that the base token address is properly configured.
        if (address(_deployConfig.baseToken) != address(ETH)) {
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
