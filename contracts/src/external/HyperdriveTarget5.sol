// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { HyperdriveAdmin } from "../internal/HyperdriveAdmin.sol";
import { HyperdriveCheckpoint } from "../internal/HyperdriveCheckpoint.sol";
import { HyperdriveLong } from "../internal/HyperdriveLong.sol";
import { HyperdriveLP } from "../internal/HyperdriveLP.sol";
import { HyperdriveMultiToken } from "../internal/HyperdriveMultiToken.sol";
import { HyperdriveShort } from "../internal/HyperdriveShort.sol";
import { HyperdriveStorage } from "../internal/HyperdriveStorage.sol";

/// @author DELV
/// @title HyperdriveTarget5
/// @notice Hyperdrive's target 5 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveTarget5 is
    HyperdriveAdmin,
    HyperdriveMultiToken,
    HyperdriveLP,
    HyperdriveLong,
    HyperdriveShort,
    HyperdriveCheckpoint
{
    /// @notice Instantiates target5.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveStorage(_config) {}

    /// LPs ///

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of capital to supply. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _apr The target APR.
    /// @param _options The options that configure how the operation is settled.
    /// @return The initial number of LP shares created.
    function initialize(
        uint256 _contribution,
        uint256 _apr,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256) {
        return _initialize(_contribution, _apr, _options);
    }

    /// Checkpoints ///

    /// @notice Allows anyone to mint a new checkpoint.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _maxIterations The number of iterations to use in the Newton's
    ///        method component of `_distributeExcessIdleSafe`. This defaults to
    ///        `LPMath.SHARE_PROCEEDS_MAX_ITERATIONS` if the specified value is
    ///        smaller than the constant.
    function checkpoint(
        uint256 _checkpointTime,
        uint256 _maxIterations
    ) external {
        _checkpoint(_checkpointTime, _maxIterations);
    }
}
