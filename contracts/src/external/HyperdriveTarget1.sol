// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { HyperdriveAdmin } from "../internal/HyperdriveAdmin.sol";
import { HyperdriveCheckpoint } from "../internal/HyperdriveCheckpoint.sol";
import { HyperdriveLong } from "../internal/HyperdriveLong.sol";
import { HyperdriveLP } from "../internal/HyperdriveLP.sol";
import { HyperdriveMultiToken } from "../internal/HyperdriveMultiToken.sol";
import { HyperdriveShort } from "../internal/HyperdriveShort.sol";
import { HyperdriveStorage } from "../internal/HyperdriveStorage.sol";

// FIXME: Natspec
abstract contract HyperdriveTarget1 is
    HyperdriveAdmin,
    HyperdriveMultiToken,
    HyperdriveLP,
    HyperdriveLong,
    HyperdriveShort,
    HyperdriveCheckpoint
{
    // FIXME: Update this Natspec
    //
    /// @notice Instantiates a Hyperdrive extras contract.
    /// @param _config The configuration of the pool.
    /// @param _linkerCodeHash The code hash of the linker contract.
    /// @param _linkerFactory The address of the linker factory.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash,
        address _linkerFactory
    ) HyperdriveStorage(_config, _linkerCodeHash, _linkerFactory) {}

    /// LPs ///

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of base to supply.
    /// @param _apr The target APR.
    /// @param _options The options that configure how the operation is settled.
    /// @return lpShares The initial number of LP shares created.
    function initialize(
        uint256 _contribution,
        uint256 _apr,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256 lpShares) {
        return _initialize(_contribution, _apr, _options);
    }

    /// @notice Allows LPs to supply liquidity for LP shares.
    /// @param _contribution The amount of base to supply.
    /// @param _minApr The minimum APR at which the LP is willing to supply.
    /// @param _maxApr The maximum APR at which the LP is willing to supply.
    /// @param _options The options that configure how the operation is settled.
    /// @return lpShares The number of LP tokens created
    function addLiquidity(
        uint256 _contribution,
        uint256 _minApr,
        uint256 _maxApr,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256 lpShares) {
        return _addLiquidity(_contribution, _minApr, _maxApr, _options);
    }

    /// Checkpoints ///

    // FIXME: Comment this.
    function checkpoint(uint256 _checkpointTime) external {
        _checkpoint(_checkpointTime);
    }
}
