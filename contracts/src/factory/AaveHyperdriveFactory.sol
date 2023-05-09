// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { AaveHyperdriveDataProvider } from "../instances/AaveHyperdriveDataProvider.sol";
import { HyperdriveFactory } from "./HyperdriveFactory.sol";
import { IPool } from "@aave/interfaces/IPool.sol";

/// @author DELV
/// @title AaveHyperdriveFactory
/// @notice Deploys hyperdrive instances and initializes them. It also holds a
///         registry of all deployed hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract AaveHyperdriveFactory is HyperdriveFactory {
    /// @notice Deploys the contract
    /// @param _governance The address which can update this factory.
    /// @param _deployer The contract which holds the bytecode and deploys new versions.
    /// @param _hyperdriveGovernance The address which is set as the governor of hyperdrive
    /// @param _fees The fees each deployed instance from this contract will have
    constructor(
        address _governance,
        IHyperdriveDeployer _deployer,
        address _hyperdriveGovernance,
        IHyperdrive.Fees memory _fees
    ) HyperdriveFactory(_governance, _deployer, _hyperdriveGovernance, _fees) {}

    /// @notice This deploys a data provider for the aave hyperdrive instance
    /// @param _config The configuration of the pool we are deploying
    /// @param _extraData An array containing the AToken in the first slot
    /// @param _linkerCodeHash The code hash from the multitoken deployer
    /// @param _linkerFactory The factory of the multitoken deployer
    function deployDataProvider(
        IHyperdrive.PoolConfig memory _config,
        bytes32[] memory _extraData,
        bytes32 _linkerCodeHash,
        address _linkerFactory
    ) internal override returns (address) {
        // Since we know this has to be the aave pool we abuse the interface to do this
        IPool pool = IAaveDeployer(address(hyperdriveDeployer)).pool();

        return (
            address(
                new AaveHyperdriveDataProvider(
                    _config,
                    _linkerCodeHash,
                    _linkerFactory,
                    IERC20(address(uint160(uint256(_extraData[0])))),
                    pool
                )
            )
        );
    }
}

interface IAaveDeployer {
    function pool() external returns (IPool);
}
