// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../interfaces/IHyperdriveDeployerCoordinator.sol";
import { IRocketTokenRETH } from "../../interfaces/IRocketTokenRETH.sol";
import { ETH } from "../../libraries/Constants.sol";
import { FixedPointMath, ONE } from "../../libraries/FixedPointMath.sol";
import { HyperdriveDeployerCoordinator } from "../HyperdriveDeployerCoordinator.sol";

/// @author DELV
/// @title RETHHyperdriveDeployerCoordinator
/// @notice The deployer coordinator for the RETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract RETHHyperdriveDeployerCoordinator is HyperdriveDeployerCoordinator {
    using SafeERC20 for ERC20;
    using FixedPointMath for uint256;

    /// @dev The Rocket Token RETH contract.
    IRocketTokenRETH internal immutable rocketTokenReth;

    /// @notice Instantiates the deployer coordinator.
    /// @param _coreDeployer The core deployer.
    /// @param _target0Deployer The target0 deployer.
    /// @param _target1Deployer The target1 deployer.
    /// @param _target2Deployer The target2 deployer.
    /// @param _target3Deployer The target3 deployer.
    /// @param _target4Deployer The target4 deployer.
    /// @param _rocketTokenReth The rETH token contract.
    constructor(
        address _coreDeployer,
        address _target0Deployer,
        address _target1Deployer,
        address _target2Deployer,
        address _target3Deployer,
        address _target4Deployer,
        IRocketTokenRETH _rocketTokenReth
    )
        HyperdriveDeployerCoordinator(
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

    /// @dev Disallows the contract to receive ether, when opening positions.
    function _checkMessageValue() internal view override {
        if (msg.value > 0) {
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
        if (_deployConfig.minimumTransactionAmount != 1e16) {
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
        // Returns the value of one RETH token in ETH.
        return rocketTokenReth.getExchangeRate();
    }
}
