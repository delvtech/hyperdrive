// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { DsrHyperdriveDataProvider } from "../instances/DsrHyperdriveDataProvider.sol";
import { HyperdriveFactory } from "./HyperdriveFactory.sol";
import { DsrManager } from "../interfaces/IMaker.sol";

/// @author DELV
/// @title DSRHyperdriveFactory
/// @notice Deploys hyperdrive instances and initializes them. It also holds a
///         registry of all deployed hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract DsrHyperdriveFactory is HyperdriveFactory {
    DsrManager internal immutable manager;

    /// @notice Deploys the contract
    /// @param _governance The address which can update this factory.
    /// @param _deployer The contract which holds the bytecode and deploys new versions.
    /// @param _hyperdriveGovernance The address which is set as the governor of hyperdrive
    /// @param _fees The fees each deployed instance from this contract will have
    constructor(
        address _governance,
        IHyperdriveDeployer _deployer,
        address _hyperdriveGovernance,
        IHyperdrive.Fees memory _fees,
        address dsrManager
    ) HyperdriveFactory(_governance, _deployer, _hyperdriveGovernance, _fees) {
        manager = DsrManager(dsrManager);
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
                new DsrHyperdriveDataProvider(
                    _config,
                    _linkerCodeHash,
                    _linkerFactory,
                    manager
                )
            )
        );
    }
}
