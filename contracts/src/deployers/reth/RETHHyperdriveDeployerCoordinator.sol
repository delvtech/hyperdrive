// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { RETHConversions } from "../../instances/reth/RETHConversions.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../interfaces/IHyperdriveDeployerCoordinator.sol";
import { IRETHHyperdriveDeployerCoordinator } from "../../interfaces/IRETHHyperdriveDeployerCoordinator.sol";
import { IRocketTokenRETH } from "../../interfaces/IRocketTokenRETH.sol";
import { ETH, RETH_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND } from "../../libraries/Constants.sol";
import { FixedPointMath, ONE } from "../../libraries/FixedPointMath.sol";
import { HyperdriveDeployerCoordinator } from "../HyperdriveDeployerCoordinator.sol";

/// @author DELV
/// @title RETHHyperdriveDeployerCoordinator
/// @notice The deployer coordinator for the RETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract RETHHyperdriveDeployerCoordinator is
    HyperdriveDeployerCoordinator,
    IRETHHyperdriveDeployerCoordinator
{
    using SafeERC20 for ERC20;
    using FixedPointMath for uint256;

    /// @notice The deployer coordinator's kind.
    string
        public constant
        override(
            HyperdriveDeployerCoordinator,
            IHyperdriveDeployerCoordinator
        ) kind = RETH_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND;

    /// @dev The Rocket Token RETH contract.
    IRocketTokenRETH internal immutable rocketTokenReth;

    /// @notice Instantiates the deployer coordinator.
    /// @param _name The deployer coordinator's name.
    /// @param _factory The factory that this deployer will be registered with.
    /// @param _coreDeployer The core deployer.
    /// @param _target0Deployer The target0 deployer.
    /// @param _target1Deployer The target1 deployer.
    /// @param _target2Deployer The target2 deployer.
    /// @param _target3Deployer The target3 deployer.
    /// @param _target4Deployer The target4 deployer.
    /// @param _rocketTokenReth The rETH token contract.
    constructor(
        string memory _name,
        address _factory,
        address _coreDeployer,
        address _target0Deployer,
        address _target1Deployer,
        address _target2Deployer,
        address _target3Deployer,
        address _target4Deployer,
        IRocketTokenRETH _rocketTokenReth
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
        rocketTokenReth = _rocketTokenReth;
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
        // If base is the deposit asset, revert because depositing as base
        // is not supported for the rETH integration.
        if (_options.asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Otherwise, transfer vault shares from the LP and approve the
        // Hyperdrive pool.
        ERC20(address(rocketTokenReth)).safeTransferFrom(
            _lp,
            address(this),
            _contribution
        );
        ERC20(address(rocketTokenReth)).forceApprove(
            address(_hyperdrive),
            _contribution
        );

        // NOTE: Return zero since this yield source isn't payable.
        return 0;
    }

    /// @notice Convert an amount of vault shares to an amount of base.
    /// @param _vaultSharesToken The vault shares asset.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IERC20 _vaultSharesToken,
        uint256 _shareAmount
    ) public view returns (uint256) {
        return RETHConversions.convertToBase(_vaultSharesToken, _shareAmount);
    }

    /// @notice Convert an amount of base to an amount of vault shares.
    /// @param _vaultSharesToken The vault shares asset.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IERC20 _vaultSharesToken,
        uint256 _baseAmount
    ) public view returns (uint256) {
        return RETHConversions.convertToShares(_vaultSharesToken, _baseAmount);
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

        // Ensure that the base token address is properly configured.
        if (address(_deployConfig.baseToken) != ETH) {
            revert IHyperdriveDeployerCoordinator.InvalidBaseToken();
        }

        // Ensure that the vault shares token address is properly configured.
        if (
            address(_deployConfig.vaultSharesToken) != address(rocketTokenReth)
        ) {
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
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    /// @return The initial vault share price of the Hyperdrive pool.
    function _getInitialVaultSharePrice(
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory // unused extra data
    ) internal view override returns (uint256) {
        return convertToBase(_deployConfig.vaultSharesToken, ONE);
    }
}
