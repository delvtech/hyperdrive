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
/// @title HyperdriveTarget3
/// @notice Hyperdrive's target 3 logic contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveTarget3 is
    HyperdriveAdmin,
    HyperdriveMultiToken,
    HyperdriveLP,
    HyperdriveLong,
    HyperdriveShort,
    HyperdriveCheckpoint
{
    /// @notice Instantiates target3.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveStorage(_config) {}

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

    /// Longs ///

    /// @notice Opens a long position.
    /// @param _baseAmount The amount of base to use when trading.
    /// @param _minOutput The minium number of bonds to receive.
    /// @param _minVaultSharePrice The minium share price at which to open the long.
    ///        This allows traders to protect themselves from opening a long in
    ///        a checkpoint where negative interest has accrued.
    /// @param _options The options that configure how the trade is settled.
    /// @return maturityTime The maturity time of the bonds.
    /// @return bondProceeds The amount of bonds the user received.
    function openLong(
        uint256 _baseAmount,
        uint256 _minOutput,
        uint256 _minVaultSharePrice,
        IHyperdrive.Options calldata _options
    ) external payable returns (uint256 maturityTime, uint256 bondProceeds) {
        return
            _openLong(_baseAmount, _minOutput, _minVaultSharePrice, _options);
    }
}
