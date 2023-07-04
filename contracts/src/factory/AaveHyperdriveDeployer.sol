// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IPool } from "@aave/interfaces/IPool.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { AaveHyperdrive } from "../instances/AaveHyperdrive.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";

/// @author DELV
/// @title AaveHyperdriveDeployer
/// @notice This is a minimal factory which contains only the logic to deploy
///         hyperdrive and is called by a more complex factory which
///         initializes the Hyperdrive instances and acts as a registry.
/// @dev We use two contracts to avoid any code size limit issues with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract AaveHyperdriveDeployer is IHyperdriveDeployer {
    IPool public immutable pool;

    constructor(IPool _pool) {
        pool = _pool;
    }

    /// @notice Deploys a copy of hyperdrive with the given params.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _dataProvider The address of the data provider.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @param _extraData This extra data contains the address of the aToken.
    /// @return The address of the newly deployed AaveHyperdrive Instance
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        bytes32[] calldata _extraData
    ) external override returns (address) {
        // Deploy the hyperdrive instance.
        IERC20 aToken = IERC20(address(uint160(uint256(_extraData[0]))));
        return (
            address(
                new AaveHyperdrive(
                    _config,
                    _dataProvider,
                    _linkerCodeHash,
                    _linkerFactory,
                    aToken,
                    pool
                )
            )
        );
    }
}
