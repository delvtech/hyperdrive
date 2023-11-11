// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626DataProvider } from "../instances/ERC4626DataProvider.sol";
import { IDataProviderDeployer } from "../interfaces/IDataProviderDeployer.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

/// @author DELV
/// @title ERC4626DataProviderFactory
/// @notice This is a minimal factory which contains only the logic to deploy
///         hyperdrive data providers and is called by a more complex factory which
///         initializes the Hyperdrive instances and acts as a registry.
/// @dev We use two contracts to avoid any code size limit issues with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626DataProviderDeployer is IDataProviderDeployer {
    /// @notice Deploys a copy of hyperdrive with the given params.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _extraData The extra data that contains the sweep targets.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @return The address of the newly deployed ERC4626DataProvider Instance
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        bytes memory _extraData
    ) external returns (address) {
        address pool = abi.decode(_extraData, (address));
        return (
            address(
                new ERC4626DataProvider(
                    _config,
                    _linkerCodeHash,
                    _linkerFactory,
                    pool
                )
            )
        );
    }
}
