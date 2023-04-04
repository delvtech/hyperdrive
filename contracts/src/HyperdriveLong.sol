// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
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
            uint256 totalGovernanceFee
        ) = _calculateOpenLong(shares, sharePrice, timeRemaining);

        // If the user gets less bonds than they paid, we are in the negative
        // interest region of the trading function.
        if (bondProceeds < _baseAmount) revert Errors.NegativeInterest();

        // Enforce min user outputs
        if (_minOutput > bondProceeds) revert Errors.OutputLimit();

        // Attribute the governance fee.
        governanceFeesAccrued += totalGovernanceFee;

        // Apply the open long to the state.
        _applyOpenLong(
            _baseAmount - totalGovernanceFee,
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

        // Perform a checkpoint at the maturity time. This ensures the long and
        // all of the other positions in the checkpoint are closed. This will
        // have no effect if the maturity time is in the future.
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
            uint256 totalGovernanceFee
        ) = _calculateCloseLong(_bondAmount, sharePrice, _maturityTime);

        // Attribute the governance fee.
        governanceFeesAccrued += totalGovernanceFee;

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
        longAggregates.averageMaturityTime = uint256(
            longAggregates.averageMaturityTime
        )
            .updateWeightedAverage(
                uint256(marketState.longsOutstanding),
                _maturityTime,
                _bondProceeds,
                true
            )
            .toUint128();

        // Update the long share price of the checkpoint.
        checkpoints[_checkpointTime].longSharePrice = uint256(
            checkpoints[_checkpointTime].longSharePrice
        )
            .updateWeightedAverage(
                uint256(
                    totalSupply[
                        AssetId.encodeAssetId(
                            AssetId.AssetIdPrefix.Long,
                            _maturityTime
                        )
                    ]
                ),
                _sharePrice,
                _bondProceeds,
                true
            )
            .toUint128();

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

        console2.log("shareAmount: %s", _baseAmount.divDown(_sharePrice));
        console2.log("shareReservesDelta: %s", _shareReservesDelta);
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
        longAggregates.averageMaturityTime = uint256(
            longAggregates.averageMaturityTime
        )
            .updateWeightedAverage(
                marketState.longsOutstanding,
                _maturityTime,
                _bondAmount,
                false
            )
            .toUint128();

        // TODO: Is it possible to abstract out the process of updating
        // aggregates in a way that is nice?
        //
        // Calculate the amount of margin that LPs provided on the long
        // position and update the base volume aggregates. Also, get the open
        // share price and update the long share price of the checkpoint.
        uint256 lpMargin;
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

            // Remove a proportional amount of the checkpoints base volume from
            // the aggregates. We calculate the margin that the LP provided
            // using this proportional base volume.
            uint256 checkpointTime = _maturityTime - positionDuration;
            uint128 proportionalBaseVolume = uint256(
                checkpoints[checkpointTime].longBaseVolume
            ).mulDown(_bondAmount.divDown(checkpointAmount)).toUint128();
            longAggregates.baseVolume -= proportionalBaseVolume;
            checkpoints[checkpointTime]
                .longBaseVolume -= proportionalBaseVolume;
            lpMargin = _bondAmount - proportionalBaseVolume;
        }

        // Reduce the amount of outstanding longs.
        marketState.longsOutstanding -= _bondAmount.toUint128();

        // Apply the updates from the curve trade to the reserves.
        marketState.shareReserves -= _shareReservesDelta.toUint128();
        marketState.bondReserves += _bondReservesDelta.toUint128();

        // Calculate the amount of liquidity that needs to be removed.
        int256 shareAdjustment = -int256(_shareProceeds - _shareReservesDelta);

        // If there is a withdraw processing, we pay out as much of the
        // withdrawal pool as possible with the the margin released and interest
        // accrued on the position to the withdrawal pool.
        if (_needsToBeFreed()) {
            // Get the open share price. This is the weighted average of the
            // share prices at the time that longs were opened, so the withdrawal
            // pool will receive as much of the long interest as possible. We
            // don't need to update this value as the weighted average will be
            // correctly computed in the event that longs are closed in the
            // first checkpoint since the balance will be reduced.
            uint256 openSharePrice = checkpoints[
                _maturityTime - positionDuration
            ].longSharePrice;

            // The withdrawal pool has preferential access to the proceeds
            // generated from closing longs. The LP proceeds when longs are
            // closed are equivalent to the proceeds of short positions.
            uint256 withdrawalProceeds = HyperdriveMath.calculateShortProceeds(
                _bondAmount,
                _shareProceeds,
                openSharePrice,
                // TODO: This allows the withdrawal pool to take all of the
                // interest as long as the checkpoint isn't minted. This is
                // probably fine, but it's worth more thought.
                _sharePrice,
                _sharePrice
            );

            // TODO: I think there may be some problems with the new withdrawal
            // pool system. In particular, it seems like short-heavy LPs will
            // get too much interest. We should write out the payoffs in a bunch
            // of different cases.
            //
            // TODO: We should explain somewhere why we decompose the withdrawal
            // pool into margin and interest.
            //
            // TODO: Is this comment accurate? Regardless, we can make it more
            // readable.
            //
            // If the short has net lost despite being still positive
            // interest we set capital recovered to 0.
            // Note - This happens when there's negative interest
            uint256 lpInterest = HyperdriveMath.calculateShortInterest(
                _bondAmount,
                openSharePrice,
                _sharePrice,
                _sharePrice
            );
            uint256 capitalFreed = withdrawalProceeds > lpInterest
                ? withdrawalProceeds - lpInterest
                : 0;

            // Pay out the withdrawal pool with the freed margin. The withdrawal
            // proceeds are split into the margin pool and the interest pool.
            // The proceeds that are distributed to the margin and interest
            // pools are removed from the pool's liquidity.
            (uint256 capitalWithdrawn, uint256 interestWithdrawn) = _freeMargin(
                capitalFreed,
                // TODO: Make sure that the withdrawal shares are actually
                // instantiated with the open share price. Think more about this as
                // it seems weird to have to convert back using an old share price
                // considering that this may not have been the share price at the
                // time the withdrawal was initiated.
                lpMargin.divDown(openSharePrice),
                lpInterest
            );
            withdrawalProceeds = capitalWithdrawn + interestWithdrawn;
            shareAdjustment -= int256(withdrawalProceeds);
        }

        // Remove the flat component of the trade as well as any LP proceeds
        // paid to the withdrawal pool from the pool's liquidity.
        _updateLiquidity(shareAdjustment);
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      opening a long. This calculation includes trading fees.
    /// @param _shareAmount The amount of shares being paid to open the long.
    /// @param _sharePrice The current share price.
    /// @param _timeRemaining The time remaining in the position.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return bondProceeds The proceeds in bonds.
    /// @return totalGovernanceFee The governance fee in shares.
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
            uint256 totalGovernanceFee
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
            uint256 governanceCurveFee,
            uint256 governanceFlatFee
        ) = _calculateFeesOutGivenSharesIn(
                _shareAmount, // amountIn
                bondProceeds, // amountOut
                _timeRemaining,
                spotPrice,
                _sharePrice
            );
        bondReservesDelta -= totalCurveFee - governanceCurveFee;
        bondProceeds -= totalCurveFee + totalFlatFee;

        // Calculate the fees owed to governance in shares.
        shareReservesDelta -= governanceCurveFee.divDown(_sharePrice);
        totalGovernanceFee = (governanceCurveFee + governanceFlatFee).divDown(
            _sharePrice
        );

        return (
            shareReservesDelta,
            bondReservesDelta,
            bondProceeds,
            totalGovernanceFee
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
    /// @return totalGovernanceFee The governance fee in shares.
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
            uint256 totalGovernanceFee
        )
    {
        // Calculate the effect that closing the long should have on the pool's
        // reserves as well as the amount of shares the trader receives for
        // selling the bonds at the market price.
        uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
        uint256 closeSharePrice = block.timestamp < _maturityTime
            ? _sharePrice
            : checkpoints[_maturityTime].sharePrice;
        (shareReservesDelta, bondReservesDelta, shareProceeds) = HyperdriveMath
            .calculateCloseLong(
                marketState.shareReserves,
                marketState.bondReserves,
                _bondAmount,
                timeRemaining,
                timeStretch,
                closeSharePrice,
                _sharePrice,
                initialSharePrice
            );

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of shares received given bonds in, we
        // subtract the fee from the share deltas so that the trader receives
        // less shares.
        //
        // TODO: There should be a way to refactor this so that the spot price
        // isn't calculated when the curve fee is 0. The bond reserves are only
        // 0 in the scenario that the LPs have fully withdrawn and the last
        // trader redeems.
        uint256 spotPrice = marketState.bondReserves > 0
            ? HyperdriveMath.calculateSpotPrice(
                marketState.shareReserves,
                marketState.bondReserves,
                initialSharePrice,
                timeRemaining,
                timeStretch
            )
            : FixedPointMath.ONE_18;
        uint256 totalCurveFee;
        uint256 totalFlatFee;
        (
            totalCurveFee,
            totalFlatFee,
            totalGovernanceFee
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
            totalGovernanceFee
        );
    }
}
