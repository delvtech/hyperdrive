// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../interfaces/IHyperdriveTargetDeployer.sol";
import { ERC4626Target1 } from "../instances/ERC4626Target1.sol";

/// @author DELV
/// @title ERC4626Target1Deployer
/// @notice This is a minimal factory which contains only the logic to deploy
///         the target1 contract and is called by a more complex factory which
///         initializes the Hyperdrive instances and acts as a registry.
/// @dev We use two contracts to avoid any code size limit issues with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Target1Deployer is IHyperdriveTargetDeployer {
    // @dev TODO: This should be removed when we update the factory.
    IERC4626 internal immutable pool;

    /// @notice Instantiates the target1 deployer.
    /// @param _pool The address of the ERC4626 pool this deployer utilizes.
    constructor(IERC4626 _pool) {
        pool = _pool;
    }

    /// @notice Deploys a target1 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @return The address of the newly deployed ERC4626Hyperdrive Instance
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes32[] memory
    ) external override returns (address) {
        // Deploy the ERC4626Target1 instance.
        return (address(new ERC4626Target1(_config, pool)));
    }
}
