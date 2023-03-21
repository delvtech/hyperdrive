// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { HyperdriveLP } from "./HyperdriveLP.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { Errors } from "./libraries/Errors.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "./libraries/YieldSpaceMath.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";

/// @author Delve
/// @title HyperdriveShort
/// @notice Implements the short accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveShort is HyperdriveLP {
    using FixedPointMath for uint256;
    using SafeCast for uint256;

    /// @notice Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    /// @param _maxDeposit The most the user expects to deposit for this trade
    /// @param _destination The address which gets credited with share tokens
    /// @param _asUnderlying If true the user is charged in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return baseDeposit The amount the user deposited for this trade
    function openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256 baseDeposit) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint and compute the amount of interest the short
        // would have received if they opened at the beginning of the checkpoint.
        // Since the short will receive interest from the beginning of the
        // checkpoint, they will receive this backdated interest back at closing.
        uint256 sharePrice = _pricePerShare();
        uint256 openSharePrice = _applyCheckpoint(
            _latestCheckpoint(),
            sharePrice
        );

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds sold to the beginning of the checkpoint.
        uint256 maturityTime = _latestCheckpoint() + positionDuration;
        uint256 timeRemaining = _calculateTimeRemaining(maturityTime);
        uint256 shareReservesDelta;
        uint256 bondReservesDelta;
        uint256 totalGovernanceFee;
        uint256 shareProceeds;
        {
            // Calculate the openShort trade deltas
            (
                shareReservesDelta,
                bondReservesDelta,
                totalGovernanceFee,
                baseDeposit,
                shareProceeds
            ) = HyperdriveMath.calculateOpenShort(
                HyperdriveMath.OpenShortCalculationParams({
                    bondAmount: _bondAmount,
                    shareReserves: marketState.shareReserves,
                    bondReserves: marketState.bondReserves,
                    sharePrice: sharePrice,
                    openSharePrice: openSharePrice,
                    initialSharePrice: initialSharePrice,
                    normalizedTimeRemaining: timeRemaining,
                    timeStretch: timeStretch,
                    curveFee: fees.curve,
                    flatFee: fees.flat,
                    governanceFee: fees.governance
                })
            );
        }

        // Attribute the governance fees.
        governanceFeesAccrued += totalGovernanceFee;

        if (_maxDeposit < baseDeposit) revert Errors.OutputLimit();
        _deposit(baseDeposit, _asUnderlying);

        // Apply the state updates caused by opening the short.
        _applyOpenShort(
            _bondAmount,
            bondReservesDelta,
            shareProceeds,
            shareReservesDelta,
            sharePrice,
            openSharePrice,
            timeRemaining,
            maturityTime
        );

        // Mint the short tokens to the trader. The ID is a concatenation of the
        // current share price and the maturity time of the shorts.
        _mint(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime),
            _destination,
            _bondAmount
        );

        return baseDeposit;
    }

    /// @notice Closes a short position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of shorts to close.
    /// @param _minOutput The minimum output of this trade.
    /// @param _destination The address which gets the proceeds from closing this short
    /// @param _asUnderlying If true the user is paid in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return proceeds The amount of base tokens produced by closing this short
    function closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256 proceeds) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint.
        uint256 sharePrice = _pricePerShare();
        _applyCheckpoint(_maturityTime, sharePrice);

        // Burn the shorts that are being closed.
        _burn(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _maturityTime),
            msg.sender,
            _bondAmount
        );

        uint256 shareReservesDelta;
        uint256 bondReservesDelta;
        uint256 totalGovernanceFee;
        uint256 sharePayment;
        {
            uint256 openSharePrice = checkpoints[
                _maturityTime - positionDuration
            ].sharePrice;
            uint256 closeSharePrice = _maturityTime <= block.timestamp
                ? checkpoints[_maturityTime].sharePrice
                : sharePrice;
            uint256 normalizedTimeRemaining = _calculateTimeRemaining(
                _maturityTime
            );

            // Calculate the pool and user deltas using the trading function.
            (
                shareReservesDelta,
                bondReservesDelta,
                totalGovernanceFee,
                sharePayment,
                proceeds
            ) = HyperdriveMath.calculateCloseShort(
                HyperdriveMath.CloseShortCalculationParams({
                    bondAmount: _bondAmount,
                    shareReserves: marketState.shareReserves,
                    bondReserves: marketState.bondReserves,
                    sharePrice: sharePrice,
                    openSharePrice: openSharePrice,
                    closeSharePrice: closeSharePrice,
                    initialSharePrice: initialSharePrice,
                    normalizedTimeRemaining: normalizedTimeRemaining,
                    timeStretch: timeStretch,
                    curveFee: fees.curve,
                    flatFee: fees.flat,
                    governanceFee: fees.governance
                })
            );
        }
        // Attribute the governance fees.
        governanceFeesAccrued += totalGovernanceFee;

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the short to the reserves and pay out the
        // withdrawal pool if necessary.
        if (block.timestamp < _maturityTime) {
            _applyCloseShort(
                _bondAmount,
                bondReservesDelta,
                sharePayment - totalGovernanceFee,
                shareReservesDelta,
                _maturityTime,
                sharePrice
            );
        }

        // Withdraw the profit to the trader. This includes the proceeds from
        // the short sale as well as the variable interest that was collected
        // on the face value of the bonds:
        // NOTE "proceeds" here is overwritten from the proceeds in shares to
        // the proceeds in bonds. The reason for this is a via-ir workaround
        (proceeds /* baseProceeds */, ) = _withdraw(
            proceeds /* shareProceeds */,
            _destination,
            _asUnderlying
        );

        // Enforce min user outputs
        if (proceeds < _minOutput) revert Errors.OutputLimit();
        return (proceeds);
    }

    /// @dev Applies an open short to the state. This includes updating the
    ///      reserves and maintaining the reserve invariants.
    /// @param _bondAmount The amount of bonds shorted.
    /// @param _bondReservesDelta The amount of bonds sold by the curve.
    /// @param _shareProceeds The proceeds from selling the bonds in shares.
    /// @param _shareReservesDelta The amount of shares paid to the curve.
    /// @param _sharePrice The share price.
    /// @param _openSharePrice The current checkpoint's share price.
    /// @param _maturityTime The maturity time of the long.
    /// @param _timeRemaining The time remaining until maturity.
    function _applyOpenShort(
        uint256 _bondAmount,
        uint256 _bondReservesDelta,
        uint256 _shareProceeds,
        uint256 _shareReservesDelta,
        uint256 _sharePrice,
        uint256 _openSharePrice,
        uint256 _timeRemaining,
        uint256 _maturityTime
    ) internal {
        // Update the average maturity time of long positions.
        {
            uint256 averageMaturityTime = uint256(
                shortAggregates.averageMaturityTime
            ).updateWeightedAverage(
                    marketState.shortsOutstanding,
                    _maturityTime,
                    _bondAmount,
                    true
                );
            shortAggregates.averageMaturityTime = averageMaturityTime
                .toUint128();
        }

        // Update the base volume of short positions.
        uint128 baseVolume = HyperdriveMath
            .calculateBaseVolume(
                _shareProceeds.mulDown(_openSharePrice),
                _bondAmount,
                _timeRemaining
            )
            .toUint128();
        shortAggregates.baseVolume += baseVolume;
        // TODO: We shouldn't need to call _latestCheckpoint() again.
        checkpoints[_latestCheckpoint()].shortBaseVolume += baseVolume;

        // Apply the trading deltas to the reserves and increase the bond buffer
        // by the amount of bonds that were shorted. We don't need to add the
        // margin or pre-paid interest to the reserves because of the way that
        // the close short accounting works.
        marketState.shareReserves -= _shareReservesDelta.toUint128();
        marketState.bondReserves += _bondReservesDelta.toUint128();
        marketState.shortsOutstanding += _bondAmount.toUint128();

        // Remove the flat component of the trade from the pool's liquidity.
        _updateLiquidity(-int256(_shareProceeds - _shareReservesDelta));

        // Since the share reserves are reduced, we need to verify that the base
        // reserves are greater than or equal to the amount of longs outstanding.
        if (
            _sharePrice.mulDown(marketState.shareReserves) <
            marketState.longsOutstanding
        ) {
            revert Errors.BaseBufferExceedsShareReserves();
        }
    }

    /// @dev Applies the trading deltas from a closed short to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of shorts that were closed.
    /// @param _bondReservesDelta The amount of bonds paid by the curve.
    /// @param _sharePayment The payment in shares required to close the short.
    /// @param _shareReservesDelta The amount of bonds paid to the curve.
    /// @param _maturityTime The maturity time of the short.
    /// @param _sharePrice The current share price
    function _applyCloseShort(
        uint256 _bondAmount,
        uint256 _bondReservesDelta,
        uint256 _sharePayment,
        uint256 _shareReservesDelta,
        uint256 _maturityTime,
        uint256 _sharePrice
    ) internal {
        // Update the short average maturity time.
        {
            uint256 averageMaturityTime = uint256(
                shortAggregates.averageMaturityTime
            ).updateWeightedAverage(
                    marketState.shortsOutstanding,
                    _maturityTime,
                    _bondAmount,
                    false
                );
            shortAggregates.averageMaturityTime = averageMaturityTime
                .toUint128();
        }

        // TODO: Is it possible to abstract out the process of updating
        // aggregates in a way that is nice?
        //
        // Calculate the amount of margin that LPs provided on the short
        // position and update the base volume aggregates.
        uint256 lpMargin;
        {
            // Get the total supply of shorts in the checkpoint of the shorts
            // being closed. If the shorts are closed before maturity, we add the
            // amount of shorts being closed since the total supply is decreased
            // when burning the short tokens.
            uint256 checkpointAmount = totalSupply[
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    _maturityTime
                )
            ];
            if (block.timestamp < _maturityTime) {
                checkpointAmount += _bondAmount;
            }

            // Remove a proportional amount of the checkpoints base volume from
            // the aggregates. We calculate the margin that the LP provided
            // using this proportional base volume.
            uint256 checkpointTime = _maturityTime - positionDuration;
            uint128 proportionalBaseVolume = uint256(
                checkpoints[checkpointTime].shortBaseVolume
            ).mulDown(_bondAmount.divDown(checkpointAmount)).toUint128();
            shortAggregates.baseVolume -= proportionalBaseVolume;
            checkpoints[checkpointTime]
                .shortBaseVolume -= proportionalBaseVolume;
            lpMargin = proportionalBaseVolume;
        }

        // Decrease the amount of shorts outstanding.
        marketState.shortsOutstanding -= _bondAmount.toUint128();

        // Apply the updates from the curve trade to the reserves.
        marketState.shareReserves += _shareReservesDelta.toUint128();
        marketState.bondReserves -= _bondReservesDelta.toUint128();

        // The flat component of the trade is added to the pool's liquidity
        // since it represents the fixed interest that the short pays to the
        // pool.
        int256 shareAdjustment = int256(_sharePayment - _shareReservesDelta);

        // If there is a withdraw processing, we pay out as much of the
        // withdrawal pool as possible with the margin released and interest
        // accrued on the position to the withdrawal pool.
        if (_needsToBeFreed()) {
            // Add capital and interest to their respective withdraw pools
            // the interest freed is the withdraw minus the margin
            uint256 withdrawalProceeds = _sharePayment;
            {
                uint256 proceedsInBase = withdrawalProceeds.mulDown(
                    _sharePrice
                );
                // TODO: Why are we calling this interest? When is this accrued?
                // We should document this.
                uint256 interest = proceedsInBase >= lpMargin
                    ? (proceedsInBase - lpMargin).divDown(_sharePrice)
                    : 0;
                (uint256 marginUsed, uint256 interestUsed) = _freeMargin(
                    withdrawalProceeds - interest,
                    lpMargin.divDown(_sharePrice),
                    interest
                );
                withdrawalProceeds = (marginUsed + interestUsed);
            }

            // The withdrawal proceeds are removed from the pool's liquidity.
            shareAdjustment -= int256(withdrawalProceeds);
        }

        // Add the flat component of the trade to the pool's liquidity and
        // remove any LP proceeds paid to the withdrawal pool from the pool's
        // liquidity.
        _updateLiquidity(shareAdjustment);
    }
}
