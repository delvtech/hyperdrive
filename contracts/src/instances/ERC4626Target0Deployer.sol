// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../interfaces/IHyperdriveTargetDeployer.sol";
import { ERC4626Target0 } from "../instances/ERC4626Target0.sol";

// FIXME: Natspec
//
/// @author DELV
/// @title ERC4626HyperdriveFactory
/// @notice This is a minimal factory which contains only the logic to deploy
///         hyperdrive and is called by a more complex factory which
///         initializes the Hyperdrive instances and acts as a registry.
/// @dev We use two contracts to avoid any code size limit issues with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Target0Deployer is IHyperdriveTargetDeployer {
    // FIXME: This shouldn't even be here once we update the factory.
    IERC4626 internal immutable pool;

    // FIXME: Natspec
    //
    constructor(IERC4626 _pool) {
        pool = _pool;
    }

    // FIXME: Natspec
    //
    /// @notice Deploys a copy of hyperdrive with the given params.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @return The address of the newly deployed ERC4626Hyperdrive Instance
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        bytes32[] memory
    ) external override returns (address) {
        // Deploy the ERC4626Target0 instance.
        return (
            address(
                new ERC4626Target0(
                    _config,
                    _linkerCodeHash,
                    _linkerFactory,
                    pool
                )
            )
        );
    }
}
