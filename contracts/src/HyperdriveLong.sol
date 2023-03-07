// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
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
abstract contract HyperdriveLong is HyperdriveBase {
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
        // backdate the bonds purchased to the beginning of the checkpoint.
        uint256 maturityTime = latestCheckpoint + positionDuration;
        uint256 timeRemaining = _calculateTimeRemaining(maturityTime);
        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 bondProceeds,
            uint256 totalGovFee
        ) = _calculateOpenLong(shares, sharePrice, timeRemaining);

        // If the user gets less bonds than they paid, we are in the negative
        // interest region of the trading function.
        if (bondProceeds < _baseAmount) revert Errors.NegativeInterest();

        // Enforce min user outputs
        if (_minOutput > bondProceeds) revert Errors.OutputLimit();

        // Attribute the governance fee.
        govFeesAccrued += totalGovFee;

        // Apply the open long to the state.
        _applyOpenLong(
            _baseAmount,
            shareReservesDelta,
            bondProceeds,
            bondReservesDelta,
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

        // Burn the longs that are being closed.
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            _maturityTime
        );
        _burn(assetId, msg.sender, _bondAmount);

        // Calculate the pool and user deltas using the trading function.
        uint256 shareReservesDelta;
        uint256 bondReservesDelta;
        uint256 shareProceeds;
        {
            uint256 totalGovFee;
            (
                shareReservesDelta,
                bondReservesDelta,
                shareProceeds,
                totalGovFee
            ) = _calculateCloseLong(_bondAmount, sharePrice, _maturityTime);

            // Attribute the governance fee.
            govFeesAccrued += totalGovFee;
        }

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the long to the reserves and pay out the
        // withdrawal pool if necessary.
        if (block.timestamp < _maturityTime) {
            _applyCloseLong(
                _bondAmount,
                bondReservesDelta,
                shareProceeds,
                shareReservesDelta,
                _maturityTime
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

    // FIXME: We could apply this update as an add liquidity action.
    //
    /// @dev Applies an open long to the state. This includes updating the
    ///      reserves and maintaining the reserve invariants.
    /// @param _baseAmount The amount of base paid by the trader.
    /// @param _shareReservesDelta The amount of shares paid to the curve.
    /// @param _bondProceeds The amount of bonds purchased by the trader.
    /// @param _bondReservesDelta The amount of bonds sold by the curve.
    /// @param _sharePrice The share price.
    /// @param _checkpointTime The time of the latest checkpoint.
    /// @param _maturityTime The maturity time of the long.
    /// @param _timeRemaining The time remaining until maturity.
    function _applyOpenLong(
        uint256 _baseAmount,
        uint256 _shareReservesDelta,
        uint256 _bondProceeds,
        uint256 _bondReservesDelta,
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
        marketState.shareReserves += _shareReservesDelta.toUint128();
        marketState.bondReserves -= _bondReservesDelta.toUint128();
        marketState.longsOutstanding += _bondProceeds.toUint128();

        // Calculate the effect that the curve trade has on the pool's APR.
        uint256 apr = HyperdriveMath.calculateAPRFromReserves(
            marketState.shareReserves,
            marketState.bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            positionDuration,
            timeStretch
        );

        // Apply the flat part of the trade to the pool's reserves.
        marketState.shareReserves += (_baseAmount.divDown(_sharePrice) -
            _shareReservesDelta).toUint128();
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

    // FIXME: A simpler way to think about this accounting scheme is to reframe
    // the withdrawal shares accounting as a "removeLiquidity" action. This will
    // play double duty with the updated flat accounting.
    //
    /// @dev Applies the trading deltas from a closed long to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of longs that were closed.
    /// @param _bondReservesDelta The bonds paid to the curve.
    /// @param _shareProceeds The proceeds received from closing the long.
    /// @param _shareReservesDelta The shares paid by the curve.
    /// @param _maturityTime The maturity time of the long.
    function _applyCloseLong(
        uint256 _bondAmount,
        uint256 _bondReservesDelta,
        uint256 _shareProceeds,
        uint256 _shareReservesDelta,
        uint256 _maturityTime
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
                aggregates.longBaseVolume -= checkpoints[checkpointTime]
                    .longBaseVolume;
                delete checkpoints[checkpointTime].longBaseVolume;
            } else {
                uint128 proportionalBaseVolume = uint256(
                    checkpoints[checkpointTime].longBaseVolume
                ).mulDown(_bondAmount.divDown(checkpointAmount)).toUint128();
                aggregates.longBaseVolume -= proportionalBaseVolume;
                checkpoints[checkpointTime]
                    .longBaseVolume -= proportionalBaseVolume;
            }
        }

        // Reduce the amount of outstanding longs.
        marketState.longsOutstanding -= _bondAmount.toUint128();

        // Apply the updates from the curve trade to the reserves.
        marketState.shareReserves -= _shareReservesDelta.toUint128();
        marketState.bondReserves += _bondReservesDelta.toUint128();

        // Calculate the effect that the curve trade has on the pool's APR.
        uint256 apr = HyperdriveMath.calculateAPRFromReserves(
            uint256(marketState.shareReserves),
            uint256(marketState.bondReserves),
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            positionDuration,
            timeStretch
        );

        // Calculate the amount of liquidity that needs to be removed.
        uint256 shareAdjustment = _shareProceeds - _shareReservesDelta;

        // FIXME: Refactor this into it's own function.
        //
        // If there are outstanding long withdrawal shares, we attribute a
        // proportional amount of the proceeds to the withdrawal pool and the
        // active LPs. Otherwise, we use simplified accounting that has the same
        // behavior but is more gas efficient. Since the difference between the
        // base reserves and the longs outstanding stays the same or gets
        // larger, we don't need to verify the reserves invariants.
        if (withdrawalState.longWithdrawalSharesOutstanding > 0) {
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
            // proceeds = c_1 * (dy / c_0 - dz) * (min(w_l, dy) / dy)
            //
            // We convert to shares at position close by dividing by c_1. If a
            // checkpoint was missed and old matured positions are being closed,
            // this will correctly attribute the extra interest to the
            // withdrawal pool.
            uint256 withdrawalAmount = withdrawalState
                .longWithdrawalSharesOutstanding < _bondAmount
                ? withdrawalState.longWithdrawalSharesOutstanding
                : _bondAmount;

            uint256 withdrawalProceeds;
            uint256 openShares = _bondAmount.divDown(openSharePrice);
            // We check if the interest rate was negative
            if (openShares > _shareProceeds) {
                // If not we do the normal calculation
                withdrawalProceeds = openShares.sub(_shareProceeds).mulDown(
                    withdrawalAmount.divDown(_bondAmount)
                );
            } else {
                // If there's negative interest the LP's position is fully wiped out and has zero value.
                withdrawalProceeds = 0;
            }

            // Update the long aggregates.
            withdrawalState.longWithdrawalSharesOutstanding -= withdrawalAmount
                .toUint128();
            withdrawalState.longWithdrawalShareProceeds += withdrawalProceeds
                .toUint128();

            // Increase the amount of liquidity to be removed.
            shareAdjustment += withdrawalProceeds;
        }

        // FIXME: This could be documented better.
        //
        // Apply the share adjustment from the reserves.
        marketState.shareReserves -= shareAdjustment.toUint128();
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
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      opening a long. This calculation includes trading fees.
    /// @param _shareAmount The amount of shares being paid to open the long.
    /// @param _sharePrice The current share price.
    /// @param _timeRemaining The time remaining in the position.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return bondProceeds The proceeds in bonds.
    /// @return totalGovFee The governance fee in shares.
    function _calculateOpenLong(
        uint256 _shareAmount,
        uint256 _sharePrice,
        uint256 _timeRemaining
    )
        internal
        view
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 bondProceeds,
            uint256 totalGovFee
        )
    {
        {
            (uint256 curveIn, uint256 curveOut, uint256 flat) = HyperdriveMath
                .calculateOpenLong(
                    marketState.shareReserves,
                    marketState.bondReserves,
                    totalSupply[AssetId._LP_ASSET_ID],
                    _shareAmount, // amountIn
                    _timeRemaining,
                    timeStretch,
                    _sharePrice,
                    initialSharePrice
                );
            shareReservesDelta = curveIn;
            bondReservesDelta = curveOut;
            bondProceeds = curveOut + flat;
        }

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of bonds received given shares in, we
        // subtract the fee from the bond deltas so that the trader receives
        // less bonds.
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            marketState.shareReserves,
            marketState.bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            _timeRemaining,
            timeStretch
        );
        (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 govCurveFee,
            uint256 govFlatFee
        ) = _calculateFeesOutGivenSharesIn(
                _shareAmount, // amountIn
                bondProceeds, // amountOut
                _timeRemaining,
                spotPrice,
                _sharePrice
            );
        bondReservesDelta -= totalCurveFee - govCurveFee;
        bondProceeds -= totalCurveFee + totalFlatFee;

        // Calculate the fees owed to governance in shares.
        totalGovFee = (govCurveFee + govFlatFee).divDown(_sharePrice);
        shareReservesDelta -= totalGovFee;

        return (
            shareReservesDelta,
            bondReservesDelta,
            bondProceeds,
            totalGovFee
        );
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      closing a long. This calculation includes trading fees.
    /// @param _bondAmount The amount of bonds being purchased to close the short.
    /// @param _sharePrice The current share price.
    /// @param _maturityTime The maturity time of the short position.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return shareProceeds The proceeds in shares of selling the bonds.
    /// @return totalGovFee The governance fee in shares.
    function _calculateCloseLong(
        uint256 _bondAmount,
        uint256 _sharePrice,
        uint256 _maturityTime
    )
        internal
        view
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 shareProceeds,
            uint256 totalGovFee
        )
    {
        // Calculate the effect that closing the long should have on the pool's
        // reserves as well as the amount of shares the trader receives for
        // selling the bonds at the market price.
        uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
        (
            shareReservesDelta,
            bondReservesDelta,
            shareProceeds
        ) = _calculateCloseLongDeltas(_bondAmount, _sharePrice, timeRemaining);

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of shares received given bonds in, we
        // subtract the fee from the share deltas so that the trader receives
        // less shares.
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            marketState.shareReserves,
            marketState.bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            timeRemaining,
            timeStretch
        );
        uint256 totalCurveFee;
        uint256 totalFlatFee;
        (
            totalCurveFee,
            totalFlatFee,
            totalGovFee
        ) = _calculateFeesOutGivenBondsIn(
            _bondAmount, // amountIn
            timeRemaining,
            spotPrice,
            _sharePrice
        );
        shareReservesDelta -= totalCurveFee;
        shareProceeds -= totalCurveFee + totalFlatFee;

        return (
            shareReservesDelta,
            bondReservesDelta,
            shareProceeds,
            totalGovFee
        );
    }

    // TODO: Document this.
    function _calculateCloseLongDeltas(
        uint256 _bondAmount,
        uint256 _sharePrice,
        uint256 _timeRemaining
    )
        internal
        view
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 shareProceeds
        )
    {
        (uint256 curveIn, uint256 curveOut, uint256 flat) = HyperdriveMath
            .calculateCloseLong(
                marketState.shareReserves,
                marketState.bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                _bondAmount,
                _timeRemaining,
                timeStretch,
                _sharePrice,
                initialSharePrice
            );
        bondReservesDelta = curveIn;
        shareReservesDelta = curveOut;
        shareProceeds = curveOut + flat;

        return (shareReservesDelta, bondReservesDelta, shareProceeds);
    }
}
