// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC4626Target3 } from "../../instances/erc4626/ERC4626Target3.sol";
import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";

/// @author DELV
/// @title ERC4626Target3Deployer
/// @notice The target3 deployer for the ERC4626Hyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Target3Deployer is IHyperdriveTargetDeployer {
    /// @notice Deploys a target3 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains the pool and sweep targets.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed ERC4626Target3 Instance.
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory _extraData,
        bytes32 _salt
    ) external returns (address) {
        IERC4626 vault = IERC4626(abi.decode(_extraData, (address)));
        return address(new ERC4626Target3{ salt: _salt }(_config, vault));
    }
}
