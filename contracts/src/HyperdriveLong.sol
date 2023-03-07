// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { HyperdriveLP } from "./HyperdriveLP.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { Errors } from "./libraries/Errors.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";

/// @author Delve
/// @title HyperdriveLong
/// @notice Implements the long accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveLong is HyperdriveLP {
    using FixedPointMath for uint256;
    using SafeCast for uint256;

    /// @notice Opens a long position.
    /// @param _baseAmount The amount of base to use when trading.
    /// @param _minOutput The minium number of bonds to receive.
    /// @param _destination The address which will receive the bonds
    /// @param _asUnderlying If true the user is charged in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return The number of bonds the user received
    function openLong(
        uint256 _baseAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256) {
        if (_baseAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Deposit the user's base.
        (uint256 shares, uint256 sharePrice) = _deposit(
            _baseAmount,
            _asUnderlying
        );

        // Perform a checkpoint.
        uint256 latestCheckpoint = _latestCheckpoint();
        _applyCheckpoint(latestCheckpoint, sharePrice);

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds purchased to the beginning of the checkpoint. We
        // reduce the purchasing power of the longs by the amount of interest
        // earned in shares.
        uint256 maturityTime = latestCheckpoint + positionDuration;
        uint256 timeRemaining = _calculateTimeRemaining(maturityTime);
        (uint256 poolBondDelta, uint256 bondProceeds) = HyperdriveMath
            .calculateOpenLong(
                marketState.shareReserves,
                marketState.bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                shares, // amountIn
                timeRemaining,
                timeStretch,
                sharePrice,
                initialSharePrice
            );

        // If the user gets less bonds than they paid we are in the negative interest
        // region of the trading function.
        if (bondProceeds < _baseAmount) revert Errors.NegativeInterest();

        {
            // Calculate the fees owed by the trader.
            uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
                marketState.shareReserves,
                marketState.bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                initialSharePrice,
                timeRemaining,
                timeStretch
            );
            (uint256 _curveFee, uint256 _flatFee) = HyperdriveMath
                .calculateFeesOutGivenIn(
                    shares, // amountIn
                    timeRemaining,
                    spotPrice,
                    sharePrice,
                    curveFee,
                    flatFee,
                    true // isShareIn
                );

            // This is a base in / bond out operation where the in is given, so we subtract the fee
            // amount from the output.
            bondProceeds -= _curveFee - _flatFee;
            poolBondDelta -= _curveFee;
        }

        // Enforce min user outputs
        if (_minOutput > bondProceeds) revert Errors.OutputLimit();

        // Apply the open long to the state.
        _applyOpenLong(
            _baseAmount,
            shares,
            bondProceeds,
            poolBondDelta,
            sharePrice,
            latestCheckpoint,
            maturityTime,
            timeRemaining
        );

        // Mint the bonds to the trader with an ID of the maturity time.
        _mint(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            _destination,
            bondProceeds
        );
        return (bondProceeds);
    }

    /// @notice Closes a long position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of longs to close.
    /// @param _minOutput The minimum base the user should receive from this trade
    /// @param _destination The address which will receive the proceeds of this sale
    /// @param _asUnderlying If true the user is paid in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return The amount of underlying the user receives.
    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint at the maturity time, this ensures the bond is closed
        // and closes all other positions in that checkpoint. This will be ignored
        // if the maturity time is in the future.
        uint256 sharePrice = _pricePerShare();
        _applyCheckpoint(_maturityTime, sharePrice);

        {
            // Burn the longs that are being closed.
            uint256 assetId = AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Long,
                _maturityTime
            );
            _burn(assetId, msg.sender, _bondAmount);
        }

        // Calculate the pool and user deltas using the trading function.
        uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
        (uint256 poolBondDelta, uint256 shareProceeds) = HyperdriveMath
            .calculateCloseLong(
                marketState.shareReserves,
                marketState.bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                _bondAmount,
                timeRemaining,
                timeStretch,
                sharePrice,
                initialSharePrice
            );
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            marketState.shareReserves,
            marketState.bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            timeRemaining,
            timeStretch
        );
        {
            (uint256 _curveFee, uint256 _flatFee) = HyperdriveMath
                .calculateFeesOutGivenIn(
                    _bondAmount, // amountIn
                    timeRemaining,
                    spotPrice,
                    sharePrice,
                    curveFee,
                    flatFee,
                    false // isShareIn
                );
            // This is a bond in / base out where the bonds are fixed, so we subtract from the base
            // out.
            shareProceeds -= _curveFee + _flatFee;
        }

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the long to the reserves and pay out the
        // withdrawal pool if necessary.
        if (block.timestamp < _maturityTime) {
            _applyCloseLong(
                _bondAmount,
                poolBondDelta,
                shareProceeds,
                _maturityTime,
                sharePrice
            );
        }

        // Withdraw the profit to the trader.
        (uint256 baseProceeds, ) = _withdraw(
            shareProceeds,
            _destination,
            _asUnderlying
        );

        // Enforce min user outputs
        if (_minOutput > baseProceeds) revert Errors.OutputLimit();

        return (baseProceeds);
    }

    /// @dev Applies an open long to the state. This includes updating the
    ///      reserves and maintaining the reserve invariants.
    /// @param _baseAmount The amount of base paid by the trader.
    /// @param _shareAmount The amount of shares paid by the trader.
    /// @param _bondProceeds The amount of bonds purchased by the trader.
    /// @param _poolBondDelta The change in the pool's bond reserves.
    /// @param _sharePrice The share price.
    /// @param _checkpointTime The time of the latest checkpoint.
    /// @param _maturityTime The maturity time of the long.
    /// @param _timeRemaining The time remaining until maturity.
    function _applyOpenLong(
        uint256 _baseAmount,
        uint256 _shareAmount,
        uint256 _bondProceeds,
        uint256 _poolBondDelta,
        uint256 _sharePrice,
        uint256 _checkpointTime,
        uint256 _maturityTime,
        uint256 _timeRemaining
    ) internal {
        // Update the average maturity time of long positions.
        {
            uint256 longAverageMaturityTime = uint256(
                aggregates.longAverageMaturityTime
            ).updateWeightedAverage(
                    uint256(marketState.longsOutstanding),
                    _maturityTime,
                    _bondProceeds,
                    true
                );
            aggregates.longAverageMaturityTime = longAverageMaturityTime
                .toUint128();
        }

        // Update the base volume of long positions.
        uint128 baseVolume = HyperdriveMath
            .calculateBaseVolume(_baseAmount, _bondProceeds, _timeRemaining)
            .toUint128();
        aggregates.longBaseVolume += baseVolume;
        checkpoints[_checkpointTime].longBaseVolume += baseVolume;

        // Apply the trading deltas to the reserves and update the amount of
        // longs outstanding.
        marketState.shareReserves += _shareAmount.toUint128();
        marketState.bondReserves -= _poolBondDelta.toUint128();
        marketState.longsOutstanding += _bondProceeds.toUint128();

        // TODO: We should fuzz test this and other trading functions to ensure
        // that the APR never goes below zero. If it does, we may need to
        // enforce additional invariants.
        //
        // Since the base buffer may have increased relative to the base
        // reserves and the bond reserves decreased, we must ensure that the
        // base reserves are greater than the longsOutstanding.
        if (
            _sharePrice.mulDown(uint256(marketState.shareReserves)) <
            marketState.longsOutstanding
        ) {
            revert Errors.BaseBufferExceedsShareReserves();
        }
    }

    /// @dev Applies the trading deltas from a closed long to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of longs that were closed.
    /// @param _poolBondDelta The amount of bonds that the pool would be
    ///        decreased by if we didn't need to account for the withdrawal
    ///        pool.
    /// @param _shareProceeds The proceeds in shares received from closing the
    ///        long.
    /// @param _maturityTime The maturity time of the long.
    /// @param _sharePrice The current price of shares
    function _applyCloseLong(
        uint256 _bondAmount,
        uint256 _poolBondDelta,
        uint256 _shareProceeds,
        uint256 _maturityTime,
        uint256 _sharePrice
    ) internal {
        // Update the long average maturity time.
        {
            uint256 longAverageMaturityTime = uint256(
                aggregates.longAverageMaturityTime
            ).updateWeightedAverage(
                    marketState.longsOutstanding,
                    _maturityTime,
                    _bondAmount,
                    false
                );
            aggregates.longAverageMaturityTime = longAverageMaturityTime
                .toUint128();
        }

        // Update the long base volume.
        // The margin used by this position which may be freed
        uint256 userMargin;
        {
            // Get the total supply of longs in the checkpoint of the longs
            // being closed. If the longs are closed before maturity, we add the
            // amount of longs being closed since the total supply is decreased
            // when burning the long tokens.
            uint256 checkpointAmount = totalSupply[
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _maturityTime)
            ];
            if (block.timestamp < _maturityTime) {
                checkpointAmount += _bondAmount;
            }

            // If all of the longs in the checkpoint are being closed, delete
            // the base volume in the checkpoint. Otherwise, decrease the base
            // volume aggregates by a proportional amount.
            uint256 checkpointTime = _maturityTime - positionDuration;
            if (_bondAmount == checkpointAmount) {
                // The total bonds minus what's paid for them
                userMargin =
                    _bondAmount -
                    checkpoints[checkpointTime].longBaseVolume;
                // Updates
                aggregates.longBaseVolume -= checkpoints[checkpointTime]
                    .longBaseVolume;
                delete checkpoints[checkpointTime].longBaseVolume;
            } else {
                uint128 proportionalBaseVolume = uint256(
                    checkpoints[checkpointTime].longBaseVolume
                ).mulDown(_bondAmount.divDown(checkpointAmount)).toUint128();
                // The total bonds minus what's paid for them
                userMargin = _bondAmount - proportionalBaseVolume;
                // Update state
                aggregates.longBaseVolume -= proportionalBaseVolume;
                checkpoints[checkpointTime]
                    .longBaseVolume -= proportionalBaseVolume;
            }
        }

        // Reduce the amount of outstanding longs.
        marketState.longsOutstanding -= _bondAmount.toUint128();

        // If there is a withdraw processing we calculate the margin freed by this position and then
        // deposit it into the withdraw pool
        if (_needsToBeFreed()) {
            // Calculate the effect that the trade has on the pool's APR.
            uint256 apr = HyperdriveMath.calculateAPRFromReserves(
                uint256(marketState.shareReserves).sub(_shareProceeds),
                uint256(marketState.bondReserves).add(_poolBondDelta),
                totalSupply[AssetId._LP_ASSET_ID],
                initialSharePrice,
                positionDuration,
                timeStretch
            );

            // Since longs are backdated to the beginning of the checkpoint and
            // interest only begins accruing when the longs are opened, we
            // exclude the first checkpoint from LP withdrawal payouts. For most
            // pools the difference will not be meaningful, and in edge cases,
            // fees can be tuned to offset the problem.
            uint256 openSharePrice = checkpoints[
                (_maturityTime - positionDuration) + checkpointDuration
            ].sharePrice;

            // Apply the LP proceeds from the trade proportionally to the long
            // withdrawal shares. The accounting for these proceeds is identical
            // to the close short accounting because LPs take the short position
            // when longs are opened. The math for the withdrawal proceeds is
            // given by:
            //
            // proceeds = c_1 * (dy / c_0 - dz)
            //
            // We convert to shares at position close by dividing by c_1. If a checkpoint
            // was missed and old matured positions are being closed, this will correctly
            // attribute the extra interest to the withdrawal pool.

            uint256 withdrawalProceeds;
            uint256 openShares = _bondAmount.divDown(openSharePrice);
            // We check if the interest rate was negative
            if (openShares > _shareProceeds) {
                // If not we do the normal calculation
                withdrawalProceeds = openShares.sub(_shareProceeds);
            } else {
                // If there's negative interest the LP's position is fully wiped out and has zero value.
                withdrawalProceeds = 0;
            }

            // Update the long aggregates.
            {
                // The short interest is the percent increase in share value times the bonds. We convert
                // to shares to match the withdraw pool:
                //   ((c - mu)/mu * bonds) / c
                uint256 userInterest = openSharePrice <= _sharePrice
                    ? (_sharePrice - openSharePrice)
                        .mulDivDown(_bondAmount, openSharePrice)
                        .divDown(_sharePrice)
                    : 0;
                // If the the short has net lost despite being still positive interest we set capital recovered to 0
                // Note - This happens when there's negative interest
                uint256 capitalFreed = withdrawalProceeds > userInterest
                    ? withdrawalProceeds - userInterest
                    : 0;
                // Call into LP to free margin
                (
                    uint256 capitalWithdrawn,
                    uint256 interestWithdrawn
                ) = _freeMargin(
                        capitalFreed,
                        userMargin.divDown(openSharePrice),
                        userInterest
                    );
                withdrawalProceeds = (capitalWithdrawn + interestWithdrawn);
            }

            // Apply the trading deltas to the reserves. These updates reflect
            // the fact that some of the reserves will be attributed to the
            // withdrawal pool. Assuming that there are some withdrawal proceeds,
            // the math for the share reserves update is given by:
            //
            // z -= dz + (dy / c_0 - dz) * (min(w_l, dy) / dy)
            marketState.shareReserves -=
                _shareProceeds.toUint128() +
                withdrawalProceeds.toUint128();
            marketState.bondReserves = HyperdriveMath
                .calculateBondReserves(
                    marketState.shareReserves,
                    totalSupply[AssetId._LP_ASSET_ID],
                    initialSharePrice,
                    apr,
                    positionDuration,
                    timeStretch
                )
                .toUint128();
        } else {
            marketState.shareReserves -= _shareProceeds.toUint128();
            marketState.bondReserves += _poolBondDelta.toUint128();
        }
    }
}
