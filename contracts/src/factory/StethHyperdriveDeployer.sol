// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { StethHyperdrive } from "../instances/StethHyperdrive.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { ILido } from "../interfaces/ILido.sol";
import { IWETH } from "../interfaces/IWETH.sol";

/// @author DELV
/// @title StethHyperdriveDeployer
/// @notice This is a minimal factory which contains only the logic to deploy
///         hyperdrive and is called by a more complex factory which
///         initializes the Hyperdrive instances and acts as a registry.
/// @dev We use two contracts to avoid any code size limit issues with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StethHyperdriveDeployer is IHyperdriveDeployer {
    /// @dev The Lido contract.
    ILido internal immutable lido;

    /// @dev The WETH token.
    IWETH internal immutable weth;

    /// @notice Initializes the factory.
    /// @param _lido The Lido contract.
    /// @param _weth The WETH token.
    constructor(ILido _lido, IWETH _weth) {
        lido = _lido;
        weth = _weth;
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
                new StethHyperdrive(
                    _config,
                    _dataProvider,
                    _linkerCodeHash,
                    _linkerFactory,
                    lido,
                    weth
                )
            )
        );
    }
}
