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
            _baseAmount - totalGovFee,
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
        _burn(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _maturityTime),
            msg.sender,
            _bondAmount
        );

        // Calculate the pool and user deltas using the trading function.
        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 shareProceeds,
            uint256 totalGovFee
        ) = _calculateCloseLong(_bondAmount, sharePrice, _maturityTime);

        // Attribute the governance fee.
        govFeesAccrued += totalGovFee;

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the long to the reserves and pay out the
        // withdrawal pool if necessary.
        if (block.timestamp < _maturityTime) {
            _applyCloseLong(
                _bondAmount,
                bondReservesDelta,
                shareProceeds,
                shareReservesDelta,
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
            uint256 averageMaturityTime = uint256(
                longAggregates.averageMaturityTime
            ).updateWeightedAverage(
                    uint256(marketState.longsOutstanding),
                    _maturityTime,
                    _bondProceeds,
                    true
                );
            longAggregates.averageMaturityTime = averageMaturityTime
                .toUint128();
        }

        // Update the base volume of long positions.
        uint128 baseVolume = HyperdriveMath
            .calculateBaseVolume(_baseAmount, _bondProceeds, _timeRemaining)
            .toUint128();
        longAggregates.baseVolume += baseVolume;
        checkpoints[_checkpointTime].longBaseVolume += baseVolume;

        // Apply the trading deltas to the reserves and update the amount of
        // longs outstanding.
        marketState.shareReserves += _shareReservesDelta.toUint128();
        marketState.bondReserves -= _bondReservesDelta.toUint128();
        marketState.longsOutstanding += _bondProceeds.toUint128();

        // Add the flat component of the trade to the pool's liquidity.
        _updateLiquidity(
            int256(_baseAmount.divDown(_sharePrice) - _shareReservesDelta)
        );

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
    /// @param _bondReservesDelta The bonds paid to the curve.
    /// @param _shareProceeds The proceeds received from closing the long.
    /// @param _shareReservesDelta The shares paid by the curve.
    /// @param _maturityTime The maturity time of the long.
    /// @param _sharePrice The current price of shares
    function _applyCloseLong(
        uint256 _bondAmount,
        uint256 _bondReservesDelta,
        uint256 _shareProceeds,
        uint256 _shareReservesDelta,
        uint256 _maturityTime,
        uint256 _sharePrice
    ) internal {
        // Update the long average maturity time.
        {
            uint256 averageMaturityTime = uint256(
                longAggregates.averageMaturityTime
            ).updateWeightedAverage(
                    marketState.longsOutstanding,
                    _maturityTime,
                    _bondAmount,
                    false
                );
            longAggregates.averageMaturityTime = averageMaturityTime
                .toUint128();
        }

        // TODO: Cleanup this code. Is it possible to abstract out the process
        // of updating aggregates in a way that is nice?
        //
        // TODO: Document this.
        uint256 margin;
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

            // TODO: Improve the documentation of this code.
            uint256 checkpointTime = _maturityTime - positionDuration;
            uint128 proportionalBaseVolume = uint256(
                checkpoints[checkpointTime].longBaseVolume
            ).mulDown(_bondAmount.divDown(checkpointAmount)).toUint128();
            longAggregates.baseVolume -= proportionalBaseVolume;
            checkpoints[checkpointTime]
                .longBaseVolume -= proportionalBaseVolume;

            // TODO: Document this.
            margin = _bondAmount - proportionalBaseVolume;
        }

        // Reduce the amount of outstanding longs.
        marketState.longsOutstanding -= _bondAmount.toUint128();

        // Apply the updates from the curve trade to the reserves.
        marketState.shareReserves -= _shareReservesDelta.toUint128();
        marketState.bondReserves += _bondReservesDelta.toUint128();

        // Calculate the amount of liquidity that needs to be removed.
        int256 shareAdjustment = -int256(_shareProceeds - _shareReservesDelta);

        // TODO: Update this comment.
        //
        // If there is a withdraw processing we calculate the margin freed by
        // this position and then deposit it into the withdraw pool.
        if (_needsToBeFreed()) {
            // Since longs are backdated to the beginning of the checkpoint and
            // interest only begins accruing when the longs are opened, we
            // exclude the first checkpoint from LP withdrawal payouts. For most
            // pools the difference will not be meaningful, and in edge cases,
            // fees can be tuned to offset the problem.
            uint256 openSharePrice = checkpoints[
                (_maturityTime - positionDuration) + checkpointDuration
            ].sharePrice;

            // The withdrawal pool has preferential access to the proceeds
            // generated from closing longs. The LP proceeds when longs are
            // closed are equivalent to the proceeds of short positions.
            uint256 withdrawalProceeds = HyperdriveMath.calculateShortProceeds(
                _bondAmount,
                _shareProceeds,
                openSharePrice,
                _sharePrice,
                _sharePrice
            );

            // TODO: Calling this user interest doesn't make sense since the
            //       user didn't accrue any interest.
            //
            // TODO: Explain why the interest doesn't need to be marked to
            //       zero if the withdrawal proceeds are zero.
            //
            // Calculate the short interest.
            uint256 userInterest = HyperdriveMath.calculateShortInterest(
                _bondAmount,
                openSharePrice,
                _sharePrice,
                _sharePrice
            );

            // TODO: This comment is really confusing.
            //
            // If the the short has net lost despite being still positive
            // interest we set capital recovered to 0.
            // Note - This happens when there's negative interest
            uint256 capitalFreed = withdrawalProceeds > userInterest
                ? withdrawalProceeds - userInterest
                : 0;

            // TODO: Improve this comment.
            //
            // Call into LP to free margin
            (uint256 capitalWithdrawn, uint256 interestWithdrawn) = _freeMargin(
                capitalFreed,
                margin.divDown(openSharePrice),
                userInterest
            );
            withdrawalProceeds = capitalWithdrawn + interestWithdrawn;

            // Increase the amount of liquidity to be removed.
            shareAdjustment -= int256(withdrawalProceeds);
        }

        // Remove the flat component of the trade as well as any LP proceeds
        // paid to the withdrawal pool from the pool's liquidity.
        _updateLiquidity(shareAdjustment);
    }

    // TODO: This is actually relatively clean, but it's a good candidate for a
    // refactor if we can find a way to avoid stack-too-deep-issues.
    //
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
        // Calculate the effect that opening the long should have on the pool's
        // reserves as well as the amount of bond the trader receives.
        (shareReservesDelta, bondReservesDelta, bondProceeds) = HyperdriveMath
            .calculateOpenLong(
                marketState.shareReserves,
                marketState.bondReserves,
                _shareAmount, // amountIn
                _timeRemaining,
                timeStretch,
                _sharePrice,
                initialSharePrice
            );

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of bonds received given shares in, we
        // subtract the fee from the bond deltas so that the trader receives
        // less bonds.
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            marketState.shareReserves,
            marketState.bondReserves,
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
        shareReservesDelta -= govCurveFee.divDown(_sharePrice);
        totalGovFee = (govCurveFee + govFlatFee).divDown(_sharePrice);

        return (
            shareReservesDelta,
            bondReservesDelta,
            bondProceeds,
            totalGovFee
        );
    }

    // TODO: This is actually relatively clean, but it's a good candidate for a
    // refactor if we can find a way to avoid stack-too-deep-issues.
    //
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
        (shareReservesDelta, bondReservesDelta, shareProceeds) = HyperdriveMath
            .calculateCloseLong(
                marketState.shareReserves,
                marketState.bondReserves,
                _bondAmount,
                timeRemaining,
                timeStretch,
                _sharePrice,
                initialSharePrice
            );

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of shares received given bonds in, we
        // subtract the fee from the share deltas so that the trader receives
        // less shares.
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            marketState.shareReserves,
            marketState.bondReserves,
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
}
