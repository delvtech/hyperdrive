// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626Target2 } from "../../instances/erc4626/ERC4626Target2.sol";
import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";

/// @author DELV
/// @title ERC4626Target2Deployer
/// @notice The target2 deployer for the ERC4626Hyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Target2Deployer is IHyperdriveTargetDeployer {
    /// @notice Deploys a target2 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains the pool and sweep targets.
    /// @return The address of the newly deployed ERC4626Target2 Instance.
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory _extraData
    ) external override returns (address) {
        // Deploy the ERC4626Target2 instance.
        IERC4626 pool = IERC4626(abi.decode(_extraData, (address)));
        return address(new ERC4626Target2(_config, pool));
    }
}
