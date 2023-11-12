// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626Hyperdrive } from "../instances/ERC4626Hyperdrive.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { IHyperdriveTargetDeployer } from "../interfaces/IHyperdriveTargetDeployer.sol";

/// @author DELV
/// @title ERC4626HyperdriveDeployer
/// @notice This is a minimal factory which contains only the logic to deploy
///         Hyperdrive and is called by a more complex factory which
///         initializes the Hyperdrive instances and acts as a registry.
/// @dev We use two contracts to avoid any code size limit issues with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626HyperdriveDeployer is IHyperdriveDeployer {

    /// @notice The contract used to deploy new instances of Hyperdrive.
    address public immutable target0Deployer;

    /// @notice The contract used to deploy new instances of Hyperdrive.
    address public immutable target1Deployer;

    constructor(address _target0Deployer, address _target1Deployer) {
        target0Deployer = _target0Deployer;
        target1Deployer = _target1Deployer;
    }

    /// @notice Deploys a Hyperdrive instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains the sweep targets.
    /// @return The address of the newly deployed ERC4626Hyperdrive Instance
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory _extraData
    ) external override returns (address) {

        (address pool, address[] memory sweepTargets) = abi.decode(_extraData, (address, address[]));

        address target0 = IHyperdriveTargetDeployer(target0Deployer).deploy(_config, _extraData, pool);
        address target1 = IHyperdriveTargetDeployer(target1Deployer).deploy(_config, _extraData, pool);

        // Deploy the ERC4626Hyperdrive instance.
        return (
            address(
                new ERC4626Hyperdrive(
                    _config,
                    target0,
                    target1,
                    IERC4626(pool),
                    sweepTargets
                )
            )
        );
    }
}
