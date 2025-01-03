// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { SavingsUSDSL2Conversions } from "../../instances/savings-usds-l2/SavingsUSDSL2Conversions.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IPSM } from "../../interfaces/IPSM.sol";
import { IHyperdriveDeployerCoordinator } from "../../interfaces/IHyperdriveDeployerCoordinator.sol";
import { SAVINGS_USDS_L2_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND } from "../../libraries/Constants.sol";
import { ONE } from "../../libraries/FixedPointMath.sol";
import { HyperdriveDeployerCoordinator } from "../HyperdriveDeployerCoordinator.sol";

/// @author DELV
/// @title SavingsUSDSL2HyperdriveDeployerCoordinator
/// @notice The deployer coordinator for the SavingsUSDSL2Hyperdrive
///         implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract SavingsUSDSL2HyperdriveDeployerCoordinator is
    HyperdriveDeployerCoordinator
{
    using SafeERC20 for ERC20;

    /// @notice The deployer coordinator's kind.
    string public constant override kind =
        SAVINGS_USDS_L2_HYPERDRIVE_DEPLOYER_COORDINATOR_KIND;

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
    /// @return value The value that should be sent in the initialize transaction.
    function _prepareInitialize(
        IHyperdrive _hyperdrive,
        address _lp,
        uint256 _contribution,
        IHyperdrive.Options memory _options
    ) internal override returns (uint256 value) {
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

        return value;
    }

    /// @notice Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IPSM _PSM,
        uint256 _shareAmount
    ) public view returns (uint256) {
        return SavingsUSDSL2Conversions.convertToBase(_PSM, _shareAmount);
    }

    /// @notice Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IPSM _PSM,
        uint256 _baseAmount
    ) public view returns (uint256) {
        return SavingsUSDSL2Conversions.convertToShares(_PSM, _baseAmount);
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
    /// @param _extraData The extra data containing the PSM address.
    function _checkPoolConfig(
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory _extraData
    ) internal view override {
        // The Sky PSM contract. This is where the base token will be
        // swapped for shares.
        require(_extraData.length >= 20, "Invalid _extraData length");
        IPSM PSM = abi.decode(_extraData, (IPSM));

        // Perform the default checks.
        super._checkPoolConfig(_deployConfig, _extraData);

        // Ensure that the vault shares token address is properly configured.
        if (address(_deployConfig.vaultSharesToken) != address(PSM.susds())) {
            revert IHyperdriveDeployerCoordinator.InvalidVaultSharesToken();
        }

        // Ensure that the base token address is properly configured.
        if (address(_deployConfig.baseToken) != address(PSM.usds())) {
            revert IHyperdriveDeployerCoordinator.InvalidBaseToken();
        }

        // Ensure that the minimum share reserves are equal to 1e15. This value
        // has been tested to prevent arithmetic overflows in the
        // `_updateLiquidity` function.
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
        bytes memory _extraData
    ) internal view override returns (uint256) {
        require(_extraData.length >= 20, "Invalid _extraData length");
        IPSM _PSM = abi.decode(_extraData, (IPSM));
        return convertToBase(_PSM, ONE);
    }
}
