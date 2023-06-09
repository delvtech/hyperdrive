// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IPool } from "@aave/interfaces/IPool.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { HyperdriveFactory } from "./HyperdriveFactory.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { AaveHyperdriveDataProvider } from "../instances/AaveHyperdriveDataProvider.sol";
import { Errors } from "../libraries/Errors.sol";

/// @author DELV
/// @title AaveHyperdriveFactory
/// @notice Deploys hyperdrive instances and initializes them. It also holds a
///         registry of all deployed hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract AaveHyperdriveFactory is HyperdriveFactory {
    // solhint-disable no-empty-blocks
    /// @notice Deploys the contract
    /// @param _governance The address which can update this factory.
    /// @param _deployer The contract which holds the bytecode and deploys new versions.
    /// @param _hyperdriveGovernance The address which is set as the governor of hyperdrive
    /// @param _feeCollector The address which should be set as the fee collector in new deployments
    /// @param _fees The fees each deployed instance from this contract will have
    /// @param _defaultPausers The default addresses which will be set to have the pauser role
    constructor(
        address _governance,
        IHyperdriveDeployer _deployer,
        address _hyperdriveGovernance,
        address _feeCollector,
        IHyperdrive.Fees memory _fees,
        address[] memory _defaultPausers
    )
        HyperdriveFactory(
            _governance,
            _deployer,
            _hyperdriveGovernance,
            _feeCollector,
            _fees,
            _defaultPausers
        )
    {}

    /// @notice Deploys a copy of hyperdrive with the given params
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @param _contribution Base token to call init with
    /// @param _apr The apr to call init with
    /// @return The hyperdrive address deployed
    function deployAndInitialize(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        bytes32[] memory,
        uint256 _contribution,
        uint256 _apr
    ) public override returns (IHyperdrive) {
        // Encode the aToken address corresponding to the base token in the
        // extra data passed to `deployAndInitialize`.
        IPool pool = IAaveDeployer(address(hyperdriveDeployer)).pool();
        address aToken = pool
            .getReserveData(address(_config.baseToken))
            .aTokenAddress;
        if (address(_config.baseToken) == address(0) || aToken == address(0)) {
            revert Errors.InvalidToken();
        }

        bytes32[] memory extraData = new bytes32[](1);
        extraData[0] = bytes32(uint256(uint160(address(aToken))));

        // Deploy and initialize the hyperdrive instance.
        return
            super.deployAndInitialize(
                _config,
                _linkerCodeHash,
                _linkerFactory,
                extraData,
                _contribution,
                _apr
            );
    }

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
