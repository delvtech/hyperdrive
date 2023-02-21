// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { HyperdriveBase } from "contracts/HyperdriveBase.sol";
import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";

/// @author Delve
/// @title HyperdriveShort
/// @notice Implements the short accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveShort is HyperdriveBase {
    using FixedPointMath for uint256;

    /// @notice Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    /// @param _maxDeposit The most the user expects to deposit for this trade
    /// @param _destination The address which gets credited with share tokens
    /// @return The amount the user deposited for this trade
    function openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        address _destination
    ) external returns (uint256) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint and compute the amount of interest the short
        // would have received if they opened at the beginning of the checkpoint.
        // Since the short will receive interest from the beginning of the
        // checkpoint, they will receive this backdated interest back at closing.
        uint256 sharePrice = pricePerShare();
        uint256 latestCheckpoint = _latestCheckpoint();
        uint256 openSharePrice = _applyCheckpoint(latestCheckpoint, sharePrice);

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds sold to the beginning of the checkpoint.
        uint256 maturityTime = latestCheckpoint + positionDuration;
        uint256 timeRemaining = _calculateTimeRemaining(maturityTime);
        uint256 shareProceeds = HyperdriveMath.calculateOpenShort(
            shareReserves,
            bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            _bondAmount,
            timeRemaining,
            timeStretch,
            sharePrice,
            initialSharePrice
        );

        {
            uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
                shareReserves,
                bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                initialSharePrice,
                timeRemaining,
                timeStretch
            );
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
            // This is a bond in / base out where the bonds are given, so we subtract from the shares
            // out.
            shareProceeds -= _curveFee + _flatFee;
        }

        // Take custody of the maximum amount the trader can lose on the short
        // and the extra interest the short will receive at closing (since the
        // proceeds of the trades are calculated using the checkpoint's open
        // share price). This extra interest can be calculated as:
        //
        // interest = (c_1 - c_0) * (dy / c_0)
        //          = (c_1 / c_0 - 1) * dy
        uint256 userDeposit;
        {
            uint256 owedInterest = (sharePrice.divDown(openSharePrice) -
                FixedPointMath.ONE_18).mulDown(_bondAmount);
            uint256 baseProceeds = shareProceeds.mulDown(sharePrice);
            userDeposit = (_bondAmount - baseProceeds) + owedInterest;
            // Enforce min user outputs
            if (_maxDeposit < userDeposit) revert Errors.OutputLimit();
            deposit(userDeposit); // max_loss + interest
        }

        // Update the average maturity time of long positions.
        shortAverageMaturityTime = shortAverageMaturityTime
            .updateWeightedAverage(
                shortsOutstanding,
                maturityTime,
                _bondAmount,
                true
            );

        // Update the base volume of short positions.
        uint256 baseVolume = HyperdriveMath.calculateBaseVolume(
            shareProceeds.mulDown(openSharePrice),
            _bondAmount,
            timeRemaining
        );
        shortBaseVolume += baseVolume;
        shortBaseVolumeCheckpoints[latestCheckpoint] += baseVolume;

        // Apply the trading deltas to the reserves and increase the bond buffer
        // by the amount of bonds that were shorted. We don't need to add the
        // margin or pre-paid interest to the reserves because of the way that
        // the close short accounting works.
        shareReserves -= shareProceeds;
        bondReserves += _bondAmount;
        shortsOutstanding += _bondAmount;

        // Since the share reserves are reduced, we need to verify that the base
        // reserves are greater than or equal to the amount of longs outstanding.
        if (sharePrice.mulDown(shareReserves) < longsOutstanding) {
            revert Errors.BaseBufferExceedsShareReserves();
        }

        // Mint the short tokens to the trader. The ID is a concatenation of the
        // current share price and the maturity time of the shorts.
        _mint(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime),
            _destination,
            _bondAmount
        );

        return (userDeposit);
    }

    /// @notice Closes a short position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of shorts to close.
    /// @param _minOutput The minimum output of this trade.
    /// @param _destination The address which gets the proceeds from closing this short
    /// @return The amount of base tokens produced by closing this short
    function closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination
    ) external returns (uint256) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint.
        uint256 sharePrice = pricePerShare();
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Burn the shorts that are being closed.
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Short,
            _maturityTime
        );
        _burn(assetId, msg.sender, _bondAmount);

        // Calculate the pool and user deltas using the trading function.
        uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
        (uint256 poolBondDelta, uint256 sharePayment) = HyperdriveMath
            .calculateCloseShort(
                shareReserves,
                bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                _bondAmount,
                timeRemaining,
                timeStretch,
                sharePrice,
                initialSharePrice,
                curveFee,
                flatFee
            );

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the short to the reserves and pay out the
        // withdrawal pool if necessary. If the position has reached maturity,
        // create a checkpoint at the maturity time if necessary.
        if (block.timestamp < _maturityTime) {
            _applyCloseShort(
                _bondAmount,
                poolBondDelta,
                sharePayment,
                sharePrice,
                _maturityTime
            );
        } else {
            // Perform a checkpoint for the short's maturity time. This ensures
            // that the matured position has been applied to the reserves.
            checkpoint(_maturityTime);
        }

        // Withdraw the profit to the trader. This includes the proceeds from
        // the short sale as well as the variable interest that was collected
        // on the face value of the bonds. The math for the short's proceeds in
        // base is given by:
        //
        // proceeds = dy - c_1 * dz + (c_1 - c_0) * (dy / c_0)
        //          = dy - c_1 * dz + (c_1 / c_0) * dy - dy
        //          = (c_1 / c_0) * dy - c_1 * dz
        //          = c_1 * (dy / c_0 - dz)
        //
        // To convert to proceeds in shares, we simply divide by the current
        // share price:
        //
        // shareProceeds = (c_1 * (dy / c_0 - dz)) / c
        uint256 openSharePrice = checkpoints[_maturityTime - positionDuration];
        uint256 closeSharePrice = sharePrice;
        if (_maturityTime <= block.timestamp) {
            closeSharePrice = checkpoints[_maturityTime];
        }
        _bondAmount = _bondAmount.divDown(openSharePrice).sub(sharePayment);
        uint256 shortProceeds = closeSharePrice.mulDown(_bondAmount).divDown(
            sharePrice
        );
        (uint256 baseProceeds, ) = withdraw(shortProceeds, _destination);

        // Enforce min user outputs
        if (baseProceeds < _minOutput) revert Errors.OutputLimit();
        return (baseProceeds);
    }

    /// @dev Applies the trading deltas from a closed short to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of shorts that were closed.
    /// @param _poolBondDelta The amount of bonds that the pool would be
    ///        decreased by if we didn't need to account for the withdrawal
    ///        pool.
    /// @param _sharePayment The payment in shares required to close the short.
    /// @param _sharePrice The current share price.
    /// @param _maturityTime The maturity time of the short.
    function _applyCloseShort(
        uint256 _bondAmount,
        uint256 _poolBondDelta,
        uint256 _sharePayment,
        uint256 _sharePrice,
        uint256 _maturityTime
    ) internal {
        // Update the short average maturity time.
        shortAverageMaturityTime = shortAverageMaturityTime
            .updateWeightedAverage(
                shortsOutstanding,
                _maturityTime,
                _bondAmount,
                false
            );

        // Update the short base volume.
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

            // If all of the shorts in the checkpoint are being closed, delete
            // the base volume in the checkpoint. Otherwise, decrease the base
            // volume aggregates by a proportional amount.
            uint256 checkpointTime = _maturityTime - positionDuration;
            if (_bondAmount == checkpointAmount) {
                shortBaseVolume -= shortBaseVolumeCheckpoints[checkpointTime];
                delete shortBaseVolumeCheckpoints[checkpointTime];
            } else {
                uint256 proportionalBaseVolume = shortBaseVolumeCheckpoints[
                    checkpointTime
                ].mulDown(_bondAmount.divDown(checkpointAmount));
                shortBaseVolume -= proportionalBaseVolume;
                shortBaseVolumeCheckpoints[
                    checkpointTime
                ] -= proportionalBaseVolume;
            }
        }

        // Decrease the amount of shorts outstanding.
        shortsOutstanding -= _bondAmount;

        // If there are outstanding short withdrawal shares, we attribute a
        // proportional amount of the proceeds to the withdrawal pool and the
        // active LPs. Otherwise, we use simplified accounting that has the same
        // behavior but is more gas efficient. Since the difference between the
        // base reserves and the longs outstanding stays the same or gets
        // larger, we don't need to verify the reserves invariants.
        if (shortWithdrawalSharesOutstanding > 0) {
            // Calculate the effect that the trade has on the pool's APR.
            uint256 apr = HyperdriveMath.calculateAPRFromReserves(
                shareReserves.add(_sharePayment),
                bondReserves.sub(_poolBondDelta),
                totalSupply[AssetId._LP_ASSET_ID],
                initialSharePrice,
                positionDuration,
                timeStretch
            );

            // Apply the LP proceeds from the trade proportionally to the short
            // withdrawal pool. The accounting for these proceeds is identical
            // to the close long accounting because LPs take on a long position when
            // shorts are opened. The math for the withdrawal proceeds is given
            // by:
            //
            // proceeds = c_1 * dz * (min(b_y, dy) / dy)
            uint256 withdrawalAmount = shortWithdrawalSharesOutstanding <
                _bondAmount
                ? shortWithdrawalSharesOutstanding
                : _bondAmount;
            uint256 withdrawalProceeds = _sharePrice
                .mulDown(_sharePayment)
                .mulDown(withdrawalAmount.divDown(_bondAmount));
            shortWithdrawalSharesOutstanding -= withdrawalAmount;
            shortWithdrawalShareProceeds += withdrawalProceeds;

            // Apply the trading deltas to the reserves. These updates reflect
            // the fact that some of the reserves will be attributed to the
            // withdrawal pool. The math for the share reserves update is given by:
            //
            // z += dz - dz * (min(b_y, dy) / dy)
            shareReserves += _sharePayment.sub(
                withdrawalProceeds.divDown(_sharePrice)
            );
            bondReserves = HyperdriveMath.calculateBondReserves(
                shareReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
        } else {
            shareReserves += _sharePayment;
            bondReserves -= _poolBondDelta;
        }
    }
}
