// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { ERC4626Conversions } from "../../instances/erc4626/ERC4626Conversions.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { IERC4626HyperdriveDeployerCoordinator } from "../../interfaces/IERC4626HyperdriveDeployerCoordinator.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../interfaces/IHyperdriveDeployerCoordinator.sol";
import { ERC4626_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND } from "../../libraries/Constants.sol";
import { ONE } from "../../libraries/FixedPointMath.sol";
import { HyperdriveDeployerCoordinator } from "../HyperdriveDeployerCoordinator.sol";

/// @author DELV
/// @title ERC4626HyperdriveDeployerCoordinator
/// @notice The deployer coordinator for the ERC4626Hyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626HyperdriveDeployerCoordinator is
    HyperdriveDeployerCoordinator,
    IERC4626HyperdriveDeployerCoordinator
{
    using SafeERC20 for ERC20;

    /// @notice The deployer coordinator's kind.
    string
        public constant
        override(
            HyperdriveDeployerCoordinator,
            IHyperdriveDeployerCoordinator
        ) kind = ERC4626_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND;

    /// @notice Instantiates the deployer coordinator.
    /// @param _name The deployer coordinator's name.
    /// @param _factory The factory that this deployer will be registered with.
    /// @param _coreDeployer The core deployer.
    /// @param _target0Deployer The target0 deployer.
    /// @param _target1Deployer The target1 deployer.
    /// @param _target2Deployer The target2 deployer.
    /// @param _target3Deployer The target3 deployer.
    /// @param _target4Deployer The target4 deployer.
    constructor(
        string memory _name,
        address _factory,
        address _coreDeployer,
        address _target0Deployer,
        address _target1Deployer,
        address _target2Deployer,
        address _target3Deployer,
        address _target4Deployer
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
    {}

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
        // If base is the deposit asset, the initialization will be paid in the
        // base token.
        address token;
        if (_options.asBase) {
            token = _hyperdrive.baseToken();
        }
        // Otherwise, the initialization will be paid in vault shares.
        else {
            token = _hyperdrive.vaultSharesToken();
        }

        // Take custody of the contribution and approve Hyperdrive to pull the
        // tokens.
        ERC20(token).safeTransferFrom(_lp, address(this), _contribution);
        ERC20(token).forceApprove(address(_hyperdrive), _contribution);

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
        return
            ERC4626Conversions.convertToBase(_vaultSharesToken, _shareAmount);
    }

    /// @notice Convert an amount of base to an amount of vault shares.
    /// @param _vaultSharesToken The vault shares asset.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IERC20 _vaultSharesToken,
        uint256 _baseAmount
    ) public view returns (uint256) {
        return
            ERC4626Conversions.convertToShares(_vaultSharesToken, _baseAmount);
    }

    /// @dev We override the message value check since this integration is
    ///      not payable.
    function _checkMessageValue() internal view override {
        if (msg.value != 0) {
            revert IHyperdriveDeployerCoordinator.NotPayable();
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

        // Ensure that the vault shares token address is non-zero.
        if (address(_deployConfig.vaultSharesToken) == address(0)) {
            revert IHyperdriveDeployerCoordinator.InvalidVaultSharesToken();
        }

        // Ensure that the base token address is properly configured.
        if (
            address(_deployConfig.baseToken) !=
            IERC4626(address(_deployConfig.vaultSharesToken)).asset()
        ) {
            revert IHyperdriveDeployerCoordinator.InvalidBaseToken();
        }

        // Ensure that the minimum share reserves are large enough to meet the
        // minimum requirements for safety.
        //
        // NOTE: Some pools may require larger minimum share reserves to be
        // considered safe. This is just a sanity check.
        if (
            _deployConfig.minimumShareReserves <
            10 ** (_deployConfig.baseToken.decimals() - 3)
        ) {
            revert IHyperdriveDeployerCoordinator.InvalidMinimumShareReserves();
        }

        // Ensure that the minimum transaction amount is large enough to meet
        // the minimum requirements for safety.
        //
        // NOTE: Some pools may require larger minimum transaction amounts to be
        // considered safe. This is just a sanity check.
        if (
            _deployConfig.minimumTransactionAmount <
            10 ** (_deployConfig.baseToken.decimals() - 3)
        ) {
            revert IHyperdriveDeployerCoordinator
                .InvalidMinimumTransactionAmount();
        }
    }

    /// @dev Gets the initial vault share price of the Hyperdrive pool.
    /// @param _deployConfig The deploy config that will be used to deploy the
    ///        pool.
    /// @return The initial vault share price of the Hyperdrive pool.
    function _getInitialVaultSharePrice(
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory // unused extra data
    ) internal view override returns (uint256) {
        return convertToBase(_deployConfig.vaultSharesToken, ONE);
    }
}
