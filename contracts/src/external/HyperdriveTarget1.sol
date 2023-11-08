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

    /// Longs ///

    /// @notice Closes a long position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of longs to close.
    /// @param _minOutput The minimum amount of base the trader will accept.
    /// @param _options The options that configure how the trade is settled.
    /// @return The amount of underlying the user receives.
    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) external returns (uint256) {
        return _closeLong(_maturityTime, _bondAmount, _minOutput, _options);
    }

    /// Shorts ///

    /// @notice Closes a short position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of shorts to close.
    /// @param _minOutput The minimum output of this trade.
    /// @param _options The options that configure how the trade is settled.
    /// @return The amount of base tokens produced by closing this short
    function closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) external returns (uint256) {
        return _closeShort(_maturityTime, _bondAmount, _minOutput, _options);
    }

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

    // FIXME: Natspec
    function removeLiquidity(
        uint256 _shares,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) external returns (uint256 baseProceeds, uint256 withdrawalShares) {
        return _removeLiquidity(_shares, _minOutput, _options);
    }

    // FIXME: Natspec
    function redeemWithdrawalShares(
        uint256 _shares,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    ) external returns (uint256 proceeds, uint256 sharesRedeemed) {
        return _redeemWithdrawalShares(_shares, _minOutput, _options);
    }

    /// Checkpoints ///

    // FIXME: Comment this.
    function checkpoint(uint256 _checkpointTime) external {
        _checkpoint(_checkpointTime);
    }
}
