// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626DataProvider } from "../instances/ERC4626DataProvider.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "../interfaces/IHyperdriveDeployer.sol";
import { HyperdriveFactory } from "./HyperdriveFactory.sol";

/// @author DELV
/// @title ERC4626HyperdriveFactory
/// @notice Deploys hyperdrive instances and initializes them. It also holds a
///         registry of all deployed hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626HyperdriveFactory is HyperdriveFactory {
    /// @dev The address of the ERC4626 pool used in this factory.
    IERC4626 internal immutable pool;

    /// @notice The sweep targets used in deployed instances. This specifies
    ///         the addresses that the fee collector can sweep to collect
    ///         incentives and redistribute them.
    address[] internal _sweepTargets;

    /// @notice Initializes the factory.
    /// @param _factoryConfig The variables that configure the factory;
    /// @param _deployer The contract that deploys new hyperdrive instances.
    /// @param _linkerFactory The linker factory.
    /// @param _linkerCodeHash The hash of the linker contract's constructor code.
    /// @param _pool The ERC4626 pool.
    /// @param _sweepTargets_ The addresses that can be swept by the fee collector.
    constructor(
        FactoryConfig memory _factoryConfig,
        IHyperdriveDeployer _deployer,
        address _linkerFactory,
        bytes32 _linkerCodeHash,
        IERC4626 _pool,
        address[] memory _sweepTargets_
    )
        HyperdriveFactory(
            _factoryConfig,
            _deployer,
            _linkerFactory,
            _linkerCodeHash
        )
    {
        // Initialize the ERC4626 pool.
        pool = _pool;

        // Initialize the default sweep targets.
        _sweepTargets = _sweepTargets_;
    }

    /// @notice Allows governance to change the sweep targets used in deployed
    ///         instances.
    /// @param _sweepTargets_ The new sweep targets.
    function updateSweepTargets(
        address[] calldata _sweepTargets_
    ) external onlyGovernance {
        _sweepTargets = _sweepTargets_;
    }

    /// @notice This deploys and initializes a new ERC4626Hyperdrive instance.
    /// @param _config The pool configuration.
    /// @param _contribution The contribution amount.
    /// @param _apr The initial spot rate.
    function deployAndInitialize(
        IHyperdrive.PoolConfig memory _config,
        bytes32[] memory,
        uint256 _contribution,
        uint256 _apr
    ) public payable override returns (IHyperdrive) {
        // Deploy and initialize the ERC4626 hyperdrive instance with the
        // default sweep targets provided as extra data.
        address[] memory sweepTargets_ = _sweepTargets;
        bytes32[] memory extraData;
        assembly ("memory-safe") {
            extraData := sweepTargets_
        }
        IHyperdrive hyperdrive = super.deployAndInitialize(
            _config,
            extraData,
            _contribution,
            _apr
        );

        // Return the hyperdrive instance.
        return hyperdrive;
    }

    /// @notice This deploys a data provider for the ERC4626 hyperdrive instance
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
                new ERC4626DataProvider(
                    _config,
                    _linkerCodeHash,
                    _linkerFactory,
                    pool
                )
            )
        );
    }

    /// @notice Gets the sweep targets.
    /// @return The sweep targets.
    function getSweepTargets() external view returns (address[] memory) {
        return _sweepTargets;
    }
}
