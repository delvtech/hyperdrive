// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../interfaces/IHyperdriveDeployerCoordinator.sol";
import { ONE } from "../../libraries/FixedPointMath.sol";
import { HyperdriveDeployerCoordinator } from "../HyperdriveDeployerCoordinator.sol";

/// @author DELV
/// @title ERC4626HyperdriveDeployerCoordinator
/// @notice The deployer coordinator for the ERC4626Hyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626HyperdriveDeployerCoordinator is HyperdriveDeployerCoordinator {
    /// @notice Instantiates the deployer coordinator.
    /// @param _coreDeployer The core deployer.
    /// @param _target0Deployer The target0 deployer.
    /// @param _target1Deployer The target1 deployer.
    /// @param _target2Deployer The target2 deployer.
    /// @param _target3Deployer The target3 deployer.
    /// @param _target4Deployer The target4 deployer.
    constructor(
        address _coreDeployer,
        address _target0Deployer,
        address _target1Deployer,
        address _target2Deployer,
        address _target3Deployer,
        address _target4Deployer
    )
        HyperdriveDeployerCoordinator(
            _coreDeployer,
            _target0Deployer,
            _target1Deployer,
            _target2Deployer,
            _target3Deployer,
            _target4Deployer
        )
    {}

    /// @notice Checks the pool configuration to ensure that it is valid.
    /// @param _deployConfig The deploy configuration of the Hyperdrive pool.
    function _checkPoolConfig(
        IHyperdrive.PoolDeployConfig memory _deployConfig
    ) internal view override {
        // Perform the default checks.
        super._checkPoolConfig(_deployConfig);

        // Ensure that the minimum share reserves are large enough to meet the
        // minimum requirements for safety.
        //
        // NOTE: Some pools may require larger minimum share reserves to be
        // considered safe. This is just a sanity check.
        if (
            _deployConfig.minimumShareReserves <
            10 ** (_deployConfig.baseToken.decimals() - 4)
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
            10 ** (_deployConfig.baseToken.decimals() - 4)
        ) {
            revert IHyperdriveDeployerCoordinator
                .InvalidMinimumTransactionAmount();
        }
    }

    /// @dev Gets the initial vault share price of the Hyperdrive pool.
    /// @param _extraData The extra data passed to the child deployers.
    /// @return The initial vault share price of the Hyperdrive pool.
    function _getInitialVaultSharePrice(
        bytes memory _extraData
    ) internal view override returns (uint256) {
        // Return the vault's current share price.
        IERC4626 vault = IERC4626(abi.decode(_extraData, (address)));
        return vault.convertToAssets(ONE);
    }
}
