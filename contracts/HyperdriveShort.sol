// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { Errors } from "./libraries/Errors.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";

/// @author Delve
/// @title HyperdriveShort
/// @notice Implements the short accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveShort is HyperdriveBase {
    using FixedPointMath for uint256;
    using SafeCast for uint256;

    /// @notice Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    /// @param _maxDeposit The most the user expects to deposit for this trade
    /// @param _destination The address which gets credited with share tokens
    /// @param _asUnderlying If true the user is charged in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return The amount the user deposited for this trade
    function openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint and compute the amount of interest the short
        // would have received if they opened at the beginning of the checkpoint.
        // Since the short will receive interest from the beginning of the
        // checkpoint, they will receive this backdated interest back at closing.
        uint256 sharePrice = _pricePerShare();
        uint256 latestCheckpoint = _latestCheckpoint();
        uint256 openSharePrice = _applyCheckpoint(latestCheckpoint, sharePrice);

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds sold to the beginning of the checkpoint.
        uint256 maturityTime = latestCheckpoint + positionDuration;
        uint256 timeRemaining = _calculateTimeRemaining(maturityTime);
        uint256 shareProceeds = HyperdriveMath.calculateOpenShort(
            state.shareReserves,
            state.bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            _bondAmount,
            timeRemaining,
            timeStretch,
            sharePrice,
            initialSharePrice
        );

        // If the user short sale is at a greater than 1 to 1 rate we are in the negative interest
        // region of the trading function.
        if (shareProceeds.mulDown(sharePrice) > _bondAmount)
            revert Errors.NegativeInterest();

        {
            uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
                state.shareReserves,
                state.bondReserves,
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
            _deposit(userDeposit, _asUnderlying); // max_loss + interest
        }

        // Update the average maturity time of long positions.
        aggregates.shortAverageMaturityTime = uint256(
            aggregates.shortAverageMaturityTime
        )
            .updateWeightedAverage(
                state.shortsOutstanding,
                maturityTime,
                _bondAmount,
                true
            )
            .toUint128();

        // Update the base volume of short positions.
        uint128 baseVolume = HyperdriveMath
            .calculateBaseVolume(
                shareProceeds.mulDown(openSharePrice),
                _bondAmount,
                timeRemaining
            )
            .toUint128();
        aggregates.shortBaseVolume += baseVolume;
        checkpoints[latestCheckpoint].shortBaseVolume += baseVolume;

        // Apply the trading deltas to the reserves and increase the bond buffer
        // by the amount of bonds that were shorted. We don't need to add the
        // margin or pre-paid interest to the reserves because of the way that
        // the close short accounting works.
        state.shareReserves -= shareProceeds.toUint128();
        state.bondReserves += _bondAmount.toUint128();
        state.shortsOutstanding += _bondAmount.toUint128();

        // Since the share reserves are reduced, we need to verify that the base
        // reserves are greater than or equal to the amount of longs outstanding.
        if (sharePrice.mulDown(state.shareReserves) < state.longsOutstanding) {
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
    /// @param _asUnderlying If true the user is paid in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return The amount of base tokens produced by closing this short
    function closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint.
        uint256 sharePrice = _pricePerShare();
        _applyCheckpoint(_maturityTime, sharePrice);

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
                state.shareReserves,
                state.bondReserves,
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
        // withdrawal pool if necessary.
        if (block.timestamp < _maturityTime) {
            _applyCloseShort(
                _bondAmount,
                poolBondDelta,
                sharePayment,
                _maturityTime
            );
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
        uint256 openSharePrice = checkpoints[_maturityTime - positionDuration]
            .sharePrice;
        uint256 closeSharePrice = sharePrice;
        if (_maturityTime <= block.timestamp) {
            closeSharePrice = checkpoints[_maturityTime].sharePrice;
        }
        // If variable interest rates are more negative than the short capital
        // deposited by the user then the user position is set to zero instead
        // of locking
        {
            uint256 userSharesAtOpen = _bondAmount.divDown(openSharePrice);
            if (userSharesAtOpen > sharePayment) {
                _bondAmount = userSharesAtOpen.sub(sharePayment);
            } else {
                _bondAmount = 0;
            }
        }
        uint256 shortProceeds = closeSharePrice.mulDown(_bondAmount).divDown(
            sharePrice
        );
        (uint256 baseProceeds, ) = _withdraw(
            shortProceeds,
            _destination,
            _asUnderlying
        );

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
    /// @param _maturityTime The maturity time of the short.
    function _applyCloseShort(
        uint256 _bondAmount,
        uint256 _poolBondDelta,
        uint256 _sharePayment,
        uint256 _maturityTime
    ) internal {
        // Update the short average maturity time.
        aggregates.shortAverageMaturityTime = uint256(
            aggregates.shortAverageMaturityTime
        )
            .updateWeightedAverage(
                state.shortsOutstanding,
                _maturityTime,
                _bondAmount,
                false
            )
            .toUint128();

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
                aggregates.shortBaseVolume -= checkpoints[checkpointTime]
                    .shortBaseVolume;
                delete checkpoints[checkpointTime].shortBaseVolume;
            } else {
                uint128 proportionalBaseVolume = uint256(
                    checkpoints[checkpointTime].shortBaseVolume
                ).mulDown(_bondAmount.divDown(checkpointAmount)).toUint128();
                aggregates.shortBaseVolume -= proportionalBaseVolume;
                checkpoints[checkpointTime]
                    .shortBaseVolume -= proportionalBaseVolume;
            }
        }

        // Decrease the amount of shorts outstanding.
        state.shortsOutstanding -= _bondAmount.toUint128();

        // If there are outstanding short withdrawal shares, we attribute a
        // proportional amount of the proceeds to the withdrawal pool and the
        // active LPs. Otherwise, we use simplified accounting that has the same
        // behavior but is more gas efficient. Since the difference between the
        // base reserves and the longs outstanding stays the same or gets
        // larger, we don't need to verify the reserves invariants.
        if (shortWithdrawalSharesOutstanding > 0) {
            // Calculate the effect that the trade has on the pool's APR.
            uint256 apr = HyperdriveMath.calculateAPRFromReserves(
                uint256(state.shareReserves).add(_sharePayment),
                uint256(state.bondReserves).sub(_poolBondDelta),
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
            //
            // We convert to shares at position close by dividing by c_1. If a checkpoint
            // was missed and old matured positions are being closed, this will correctly
            // attribute the extra interest to the withdrawal pool.
            uint256 withdrawalAmount = shortWithdrawalSharesOutstanding <
                _bondAmount
                ? shortWithdrawalSharesOutstanding
                : _bondAmount;
            uint256 withdrawalProceeds = _sharePayment.mulDown(
                withdrawalAmount.divDown(_bondAmount)
            );
            shortWithdrawalSharesOutstanding -= withdrawalAmount;
            shortWithdrawalShareProceeds += withdrawalProceeds;

            // Apply the trading deltas to the reserves. These updates reflect
            // the fact that some of the reserves will be attributed to the
            // withdrawal pool. The math for the share reserves update is given by:
            //
            // z += dz - dz * (min(b_y, dy) / dy)
            state.shareReserves +=
                _sharePayment.toUint128() -
                withdrawalProceeds.toUint128();
            state.bondReserves = HyperdriveMath
                .calculateBondReserves(
                    state.shareReserves,
                    totalSupply[AssetId._LP_ASSET_ID],
                    initialSharePrice,
                    apr,
                    positionDuration,
                    timeStretch
                )
                .toUint128();
        } else {
            state.shareReserves += _sharePayment.toUint128();
            state.bondReserves -= _poolBondDelta.toUint128();
        }
    }
}
