// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../interfaces/IHyperdriveAdminController.sol";
import { HyperdriveAdmin } from "../internal/HyperdriveAdmin.sol";
import { HyperdriveCheckpoint } from "../internal/HyperdriveCheckpoint.sol";
import { HyperdriveLong } from "../internal/HyperdriveLong.sol";
import { HyperdriveLP } from "../internal/HyperdriveLP.sol";
import { HyperdriveMultiToken } from "../internal/HyperdriveMultiToken.sol";
import { HyperdriveShort } from "../internal/HyperdriveShort.sol";
import { HyperdriveStorage } from "../internal/HyperdriveStorage.sol";

/// @author DELV
/// @title HyperdriveTarget4
/// @notice Hyperdrive's target 4 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveTarget4 is
    HyperdriveAdmin,
    HyperdriveMultiToken,
    HyperdriveLP,
    HyperdriveLong,
    HyperdriveShort,
    HyperdriveCheckpoint
{
    /// @notice Instantiates target4.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController
    ) HyperdriveStorage(_config, __adminController) {}

    /// LPs ///

    /// @notice Allows an LP to burn shares and withdraw from the pool.
    /// @param _lpShares The LP shares to burn.
    /// @param _minOutputPerShare The minimum amount the LP expects to receive
    ///        for each withdrawal share that is burned. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _options The options that configure how the operation is settled.
    /// @return The amount the LP removing liquidity receives. The
    ///        units of this quantity are either base or vault shares, depending
    ///        on the value of `_options.asBase`.
    /// @return The base that the LP receives buys out some of their LP shares,
    ///         but it may not be sufficient to fully buy the LP out. In this
    ///         case, the LP receives withdrawal shares equal in value to the
    ///         present value they are owed. As idle capital becomes available,
    ///         the pool will buy back these shares.
    function removeLiquidity(
        uint256 _lpShares,
        uint256 _minOutputPerShare,
        IHyperdrive.Options calldata _options
    ) external returns (uint256, uint256) {
        return _removeLiquidity(_lpShares, _minOutputPerShare, _options);
    }

    /// @notice Redeems withdrawal shares by giving the LP a pro-rata amount of
    ///         the withdrawal pool's proceeds. This function redeems the
    ///         maximum amount of the specified withdrawal shares given the
    ///         amount of withdrawal shares ready to withdraw.
    /// @param _withdrawalShares The withdrawal shares to redeem.
    /// @param _minOutputPerShare The minimum amount the LP expects to
    ///        receive for each withdrawal share that is burned. The units of
    ///        this quantity are either base or vault shares, depending on the
    ///        value of `_options.asBase`.
    /// @param _options The options that configure how the operation is settled.
    /// @return The amount the LP received. The units of this quantity are
    ///         either base or vault shares, depending on the value of
    ///         `_options.asBase`.
    /// @return The amount of withdrawal shares that were redeemed.
    function redeemWithdrawalShares(
        uint256 _withdrawalShares,
        uint256 _minOutputPerShare,
        IHyperdrive.Options calldata _options
    ) external returns (uint256, uint256) {
        return
            _redeemWithdrawalShares(
                _withdrawalShares,
                _minOutputPerShare,
                _options
            );
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
