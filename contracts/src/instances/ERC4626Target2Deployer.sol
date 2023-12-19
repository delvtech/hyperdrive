// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../interfaces/IHyperdriveTargetDeployer.sol";
import { ERC4626Target2 } from "../instances/ERC4626Target2.sol";

/// @author DELV
/// @title ERC4626Target2Deployer
/// @notice This is a minimal factory which contains only the logic to deploy
///         the target2 contract and is called by a more complex factory which
///         initializes the Hyperdrive instances and acts as a registry.
/// @dev We use two contracts to avoid any code size limit issues with Hyperdrive.
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
        (address pool, ) = abi.decode(_extraData, (address, address[]));
        // Deploy the ERC4626Target2 instance.
        return address(new ERC4626Target2(_config, IERC4626(pool)));
    }
}
