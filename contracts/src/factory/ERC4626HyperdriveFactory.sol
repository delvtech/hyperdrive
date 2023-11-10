// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626Target0 } from "../instances/ERC4626Target0.sol";
import { ERC4626Target1 } from "../instances/ERC4626Target1.sol";
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
    /// @notice The sweep targets used in deployed instances. This specifies
    ///         the addresses that the fee collector can sweep to collect
    ///         incentives and redistribute them.
    address[] internal _sweepTargets;

    /// @notice Initializes the factory.
    /// @param _factoryConfig The variables that configure the factory;
    /// @param __sweepTargets The addresses that can be swept by the fee collector.
    constructor(
        FactoryConfig memory _factoryConfig,
        address[] memory __sweepTargets
    ) HyperdriveFactory(_factoryConfig) {
        // Initialize the default sweep targets.
        _sweepTargets = __sweepTargets;
    }

    /// @notice Allows governance to change the sweep targets used in deployed
    ///         instances.
    /// @param __sweepTargets The new sweep targets.
    function updateSweepTargets(
        address[] calldata __sweepTargets
    ) external onlyGovernance {
        _sweepTargets = __sweepTargets;
    }

    /// @notice This deploys and initializes a new ERC4626Hyperdrive instance.
    /// @param _config The pool configuration.
    /// @param _contribution The contribution amount.
    /// @param _apr The initial spot rate.
    /// @param _initializeExtraData The extra data for the `initialize` call.
    /// @param _pool The ERC4626 compatible yield source.
    function deployAndInitialize(
        IHyperdrive.PoolConfig memory _config,
        uint256 _contribution,
        uint256 _apr,
        bytes memory _initializeExtraData,
        bytes32[] memory, // unused
        address _pool
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
            _contribution,
            _apr,
            _initializeExtraData,
            extraData,
            _pool
        );

        // Return the hyperdrive instance.
        return hyperdrive;
    }

    /// @notice Gets the sweep targets.
    /// @return The sweep targets.
    function getSweepTargets() external view returns (address[] memory) {
        return _sweepTargets;
    }
}
