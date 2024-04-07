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
/// @title HyperdriveTarget2
/// @notice Hyperdrive's target 2 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveTarget2 is
    HyperdriveAdmin,
    HyperdriveMultiToken,
    HyperdriveLP,
    HyperdriveLong,
    HyperdriveShort,
    HyperdriveCheckpoint
{
    /// @notice Instantiates target2.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveStorage(_config) {}

    /// Longs ///

    /// @notice Closes a long position with a specified maturity time.
    /// @param _maturityTime The maturity time of the long.
    /// @param _bondAmount The amount of longs to close.
    /// @param _minOutput The minimum proceeds the trader will accept. The units
    ///        of this quantity are either base or vault shares, depending on
    ///        the value of `_options.asBase`.
    /// @param _options The options that configure how the trade is settled.
    /// @return The proceeds the user receives. The units of this quantity are
    ///         either base or vault shares, depending on the value of
    ///         `_options.asBase`.
    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) external returns (uint256) {
        return _closeLong(_maturityTime, _bondAmount, _minOutput, _options);
    }

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
}
