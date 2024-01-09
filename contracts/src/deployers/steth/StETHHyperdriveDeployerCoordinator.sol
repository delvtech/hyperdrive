// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ILido } from "../../interfaces/ILido.sol";
import { FixedPointMath, ONE } from "../../libraries/FixedPointMath.sol";
import { HyperdriveDeployerCoordinator } from "../HyperdriveDeployerCoordinator.sol";

/// @author DELV
/// @title StETHHyperdriveDeployerCoordinator
/// @notice The deployer coordinator for the StETHHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StETHHyperdriveDeployerCoordinator is HyperdriveDeployerCoordinator {
    using FixedPointMath for uint256;

    /// @notice The Lido contract.
    ILido public immutable lido;

    /// @notice Instantiates the deployer coordinator.
    /// @param _coreDeployer The core deployer.
    /// @param _target0Deployer The target0 deployer.
    /// @param _target1Deployer The target1 deployer.
    /// @param _target2Deployer The target2 deployer.
    /// @param _target3Deployer The target3 deployer.
    /// @param _lido The Lido contract.
    constructor(
        address _coreDeployer,
        address _target0Deployer,
        address _target1Deployer,
        address _target2Deployer,
        address _target3Deployer,
        ILido _lido
    )
        HyperdriveDeployerCoordinator(
            _coreDeployer,
            _target0Deployer,
            _target1Deployer,
            _target2Deployer,
            _target3Deployer
        )
    {
        lido = _lido;
    }

    /// @dev Gets the initial share price of the Hyperdrive pool.
    /// @return The initial share price of the Hyperdrive pool.
    function _getInitialSharePrice(
        bytes memory // unused extra data
    ) internal view override returns (uint256) {
        // Return the stETH's current share price.
        return lido.getTotalPooledEther().divDown(lido.getTotalShares());
    }
}
