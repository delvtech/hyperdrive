// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../interfaces/IHyperdriveAdminController.sol";
import { HyperdriveAdmin } from "../internal/HyperdriveAdmin.sol";
import { HyperdriveCheckpoint } from "../internal/HyperdriveCheckpoint.sol";
import { HyperdriveLong } from "../internal/HyperdriveLong.sol";
import { HyperdriveLP } from "../internal/HyperdriveLP.sol";
import { HyperdriveMultiToken } from "../internal/HyperdriveMultiToken.sol";
import { HyperdrivePair } from "../internal/HyperdrivePair.sol";
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
    HyperdrivePair,
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

    /// Pairs ///

    /// @notice Mints a pair of long and short positions that directly match
    ///         each other. The amount of long and short positions that are
    ///         created is equal to the base value of the deposit. These
    ///         positions are sent to the provided destinations.
    /// @param _amount The amount of capital provided to open the long. The
    ///        units of this quantity are either base or vault shares, depending
    ///        on the value of `_options.asBase`.
    /// @param _minOutput The minimum number of bonds to receive.
    /// @param _minVaultSharePrice The minimum vault share price at which to
    ///        mint the bonds. This allows traders to protect themselves from
    ///        opening a long in a checkpoint where negative interest has
    ///        accrued.
    /// @param _options The pair options that configure how the trade is settled.
    /// @return maturityTime The maturity time of the new long and short positions.
    /// @return bondAmount The bond amount of the new long and short positoins.
    function mint(
        uint256 _amount,
        uint256 _minOutput,
        uint256 _minVaultSharePrice,
        IHyperdrive.PairOptions calldata _options
    ) external payable returns (uint256 maturityTime, uint256 bondAmount) {
        return _mint(_amount, _minOutput, _minVaultSharePrice, _options);
    }

    /// @dev Burns a pair of long and short positions that directly match each
    ///      other. The capital underlying these positions is released to the
    ///      trader burning the positions.
    /// @param _maturityTime The maturity time of the long and short positions.
    /// @param _bondAmount The amount of longs and shorts to close.
    /// @param _minOutput The minimum amount of proceeds to receive.
    /// @param _options The options that configure how the trade is settled.
    /// @return proceeds The proceeds the user receives. The units of this
    ///         quantity are either base or vault shares, depending on the value
    ///         of `_options.asBase`.
    function burn(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) external returns (uint256 proceeds) {
        return _burn(_maturityTime, _bondAmount, _minOutput, _options);
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
