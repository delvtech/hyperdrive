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
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController
    ) HyperdriveStorage(_config, __adminController) {}

    /// Shorts ///

    /// @notice Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    /// @param _maxDeposit The most the user expects to deposit for this trade.
    ///        The units of this quantity are either base or vault shares,
    ///        depending on the value of `_options.asBase`.
    /// @param _minVaultSharePrice The minimum vault share price at which to
    ///        open the short. This allows traders to protect themselves from
    ///        opening a short in a checkpoint where negative interest has
    ///        accrued.
    /// @param _options The options that configure how the trade is settled.
    /// @return The maturity time of the short.
    /// @return The amount the user deposited for this trade. The units of this
    ///         quantity are either base or vault shares, depending on the value
    ///         of `_options.asBase`.
    function openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        uint256 _minVaultSharePrice,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256, uint256) {
        return
            _openShort(_bondAmount, _maxDeposit, _minVaultSharePrice, _options);
    }

    /// Longs ///

    /// @notice Opens a long position.
    /// @param _amount The amount of capital provided to open the long. The
    ///        units of this quantity are either base or vault shares, depending
    ///        on the value of `_options.asBase`.
    /// @param _minOutput The minimum number of bonds to receive.
    /// @param _minVaultSharePrice The minimum vault share price at which to
    ///        open the long. This allows traders to protect themselves from
    ///        opening a long in a checkpoint where negative interest has
    ///        accrued.
    /// @param _options The options that configure how the trade is settled.
    /// @return The maturity time of the bonds.
    /// @return The amount of bonds the user received.
    function openLong(
        uint256 _amount,
        uint256 _minOutput,
        uint256 _minVaultSharePrice,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256, uint256) {
        return _openLong(_amount, _minOutput, _minVaultSharePrice, _options);
    }
}
