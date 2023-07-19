// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveFactory } from "./HyperdriveFactory.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { ILido } from "../interfaces/ILido.sol";
import { IWETH } from "../interfaces/IWETH.sol";
import { StethHyperdriveDataProvider } from "../instances/StethHyperdriveDataProvider.sol";

/// @author DELV
/// @title StethHyperdriveFactory
/// @notice Deploys StethHyperdrive instances and initializes them. It also
///         holds a registry of all deployed hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StethHyperdriveFactory is HyperdriveFactory {
    /// @dev The Lido contract.
    ILido internal immutable lido;

    /// @notice Deploys the contract
    /// @param _factoryConfig The variables that configure the factory;
    /// @param _deployer The contract which holds the bytecode and deploys new versions.
    /// @param _linkerFactory The address of the linker factory.
    /// @param _linkerCodeHash The hash of the linker contract's constructor code.
    /// @param _lido The Lido contract.
    constructor(
        FactoryConfig memory _factoryConfig,
        IHyperdriveDeployer _deployer,
        address _linkerFactory,
        bytes32 _linkerCodeHash,
        ILido _lido
    )
        HyperdriveFactory(
            _factoryConfig,
            _deployer,
            _linkerFactory,
            _linkerCodeHash
        )
    {
        lido = _lido;
    }

    /// @notice This deploys a data provider for the aave hyperdrive instance
    /// @param _config The configuration of the pool we are deploying
    /// @param _linkerCodeHash The code hash from the multitoken deployer
    /// @param _linkerFactory The factory of the multitoken deployer
    function deployDataProvider(
        IHyperdrive.PoolConfig memory _config,
        bytes32[] memory,
        bytes32 _linkerCodeHash,
        address _linkerFactory
    ) internal override returns (address) {
        return (
            address(
                new StethHyperdriveDataProvider(
                    _config,
                    _linkerCodeHash,
                    _linkerFactory,
                    lido
                )
            )
        );
    }
}
