// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626Hyperdrive } from "../instances/ERC4626Hyperdrive.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";

/// @author DELV
/// @title ERC4626HyperdriveFactory
/// @notice This is a minimal factory which contains only the logic to deploy
///         hyperdrive and is called by a more complex factory which
///         initializes the Hyperdrive instances and acts as a registry.
/// @dev We use two contracts to avoid any code size limit issues with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626HyperdriveDeployer is IHyperdriveDeployer {
    IERC4626 internal immutable pool;

    constructor(IERC4626 _pool) {
        pool = _pool;
    }

    /// @notice Deploys a copy of hyperdrive with the given params.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _dataProvider The address of the data provider.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        bytes32[] calldata
    ) external override returns (address) {
        return (
            address(
                new ERC4626Hyperdrive(
                    _config,
                    _dataProvider,
                    _linkerCodeHash,
                    _linkerFactory,
                    pool
                )
            )
        );
    }
}
