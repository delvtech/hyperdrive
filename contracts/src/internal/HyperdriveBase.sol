// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveEvents } from "../interfaces/IHyperdriveEvents.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";
import { LPMath } from "../libraries/LPMath.sol";
import { YieldSpaceMath } from "../libraries/YieldSpaceMath.sol";
import { SafeCast } from "../libraries/SafeCast.sol";
import { HyperdriveStorage } from "./HyperdriveStorage.sol";

/// @author DELV
/// @title HyperdriveBase
/// @notice The Hyperdrive base contract that provides a set of helper methods
///         and defines the functions that must be overridden by implementations.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveBase is IHyperdriveEvents, HyperdriveStorage {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// Yield Source ///

    /// @dev Process a deposit in either base or vault shares.
    /// @param _amount The amount of capital to deposit. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _options The options that configure how the deposit is
    ///        settled. In particular, the currency used in the deposit is
    ///        specified here. Aside from those options, yield sources can
    ///        choose to implement additional options.
    /// @return sharesMinted The shares created by this deposit.
    /// @return vaultSharePrice The vault share price.
    function _deposit(
        uint256 _amount,
        IHyperdrive.Options calldata _options
    ) internal returns (uint256 sharesMinted, uint256 vaultSharePrice) {
        // WARN: This logic doesn't account for slippage in the conversion
        // from base to shares. If deposits to the yield source incur
        // slippage, this logic will be incorrect.
        //
        // The amount of shares minted is equal to the input amount if the
        // deposit asset is in shares.
        sharesMinted = _amount;

        // Deposit with either base or shares depending on the provided options.
        uint256 refund;
        if (_options.asBase) {
            // Process the deposit in base.
            (sharesMinted, refund) = _depositWithBase(
                _amount,
                _options.extraData
            );
        } else {
            // The refund is equal to the full message value since ETH will
            // never be a shares asset.
            refund = msg.value;

            // Process the deposit in shares.
            _depositWithShares(_amount, _options.extraData);
        }

        // Calculate the vault share price.
        vaultSharePrice = _pricePerVaultShare();

        // Return excess ether that was sent to the contract.
        if (refund > 0) {
            (bool success, ) = payable(msg.sender).call{ value: refund }("");
            if (!success) {
                revert IHyperdrive.TransferFailed();
            }
        }

        return (sharesMinted, vaultSharePrice);
    }

    /// @dev Process a withdrawal and send the proceeds to the destination.
    /// @param _shares The vault shares to withdraw from the yield source.
    /// @param _vaultSharePrice The vault share price.
    /// @param _options The options that configure how the withdrawal is
    ///        settled. In particular, the destination and currency used in the
    ///        withdrawal are specified here. Aside from those options, yield
    ///        sources can choose to implement additional options.
    /// @return amountWithdrawn The proceeds of the withdrawal. The units of
    ///        this quantity are either base or vault shares, depending on the
    ///        value of `_options.asBase`.
    function _withdraw(
        uint256 _shares,
        uint256 _vaultSharePrice,
        IHyperdrive.Options calldata _options
    ) internal returns (uint256 amountWithdrawn) {
        // NOTE: Round down to underestimate the base proceeds.
        //
        // Correct for any error that crept into the calculation of the share
        // amount by converting the shares to base and then back to shares
        // using the vault's share conversion logic.
        uint256 baseAmount = _shares.mulDown(_vaultSharePrice);
        _shares = _convertToShares(baseAmount);

        // If we're withdrawing zero shares, short circuit and return 0.
        if (_shares == 0) {
            return 0;
        }

        // Withdraw in either base or shares depending on the provided options.
        amountWithdrawn = _shares;
        if (_options.asBase) {
            // Process the withdrawal in base.
            amountWithdrawn = _withdrawWithBase(
                _shares,
                _options.destination,
                _options.extraData
            );
        } else {
            // Process the withdrawal in shares.
            _withdrawWithShares(
                _shares,
                _options.destination,
                _options.extraData
            );
        }

        return amountWithdrawn;
    }

    /// @dev Loads the share price from the yield source.
    /// @return vaultSharePrice The current vault share price.
    function _pricePerVaultShare()
        internal
        view
        returns (uint256 vaultSharePrice)
    {
        return _convertToBase(ONE);
    }

    /// @dev Accepts a deposit from the user in base.
    /// @param _baseAmount The base amount to deposit.
    /// @param _extraData The extra data to use in the deposit.
    /// @return sharesMinted The shares that were minted in the deposit.
    /// @return refund The amount of ETH to refund. This should be zero for
    ///         yield sources that don't accept ETH.
    function _depositWithBase(
        uint256 _baseAmount,
        bytes calldata _extraData
    ) internal virtual returns (uint256 sharesMinted, uint256 refund);

    /// @dev Process a deposit in vault shares.
    /// @param _shareAmount The vault shares amount to deposit.
    /// @param _extraData The extra data to use in the deposit.
    function _depositWithShares(
        uint256 _shareAmount,
        bytes calldata _extraData
    ) internal virtual;

    /// @dev Process a withdrawal in base and send the proceeds to the
    ///      destination.
    /// @param _shareAmount The amount of vault shares to withdraw.
    /// @param _destination The destination of the withdrawal.
    /// @param _extraData The extra data used to settle the withdrawal.
    /// @return amountWithdrawn The amount of base withdrawn.
    function _withdrawWithBase(
        uint256 _shareAmount,
        address _destination,
        bytes calldata _extraData
    ) internal virtual returns (uint256 amountWithdrawn);

    /// @dev Process a withdrawal in vault shares and send the proceeds to the
    ///      destination.
    /// @param _shareAmount The amount of vault shares to withdraw.
    /// @param _destination The destination of the withdrawal.
    /// @param _extraData The extra data used to settle the withdrawal.
    function _withdrawWithShares(
        uint256 _shareAmount,
        address _destination,
        bytes calldata _extraData
    ) internal virtual;

    /// @dev A yield source dependent check that prevents ether from being
    ///      transferred to Hyperdrive instances that don't accept ether.
    function _checkMessageValue() internal view virtual;

    /// @dev A yield source dependent check that verifies that the provided
    ///      options are valid. The default check is that the destination is
    ///      non-zero to prevent users from accidentally transferring funds
    ///      to the zero address. Custom integrations can override this to
    ///      implement additional checks.
    /// @param _options The provided options for the transaction.
    function _checkOptions(
        IHyperdrive.Options calldata _options
    ) internal pure virtual {
        if (_options.destination == address(0)) {
            revert IHyperdrive.RestrictedZeroAddress();
        }
    }

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return baseAmount The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal view virtual returns (uint256 baseAmount);

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return shareAmount The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal view virtual returns (uint256 shareAmount);

    /// @dev Gets the total amount of shares held by the pool in the yield
    ///      source.
    /// @return shareAmount The total amount of shares.
    function _totalShares() internal view virtual returns (uint256 shareAmount);

    /// Pause ///

    /// @dev Blocks a function execution if the contract is paused.
    modifier isNotPaused() {
        if (_marketState.isPaused) {
            revert IHyperdrive.PoolIsPaused();
        }
        _;
    }

    /// Checkpoint ///

    /// @dev Creates a new checkpoint if necessary.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _maxIterations The number of iterations to use in the Newton's
    ///        method component of `_distributeExcessIdleSafe`. This defaults to
    ///        `LPMath.SHARE_PROCEEDS_MAX_ITERATIONS` if the specified value is
    ///        smaller than the constant.
    /// @param _isTrader A boolean indicating whether or not the checkpoint was
    ///        minted by a trader or by someone calling checkpoint directly.
    /// @return openVaultSharePrice The open vault share price of the latest
    ///         checkpoint.
    function _applyCheckpoint(
        uint256 _checkpointTime,
        uint256 _vaultSharePrice,
        uint256 _maxIterations,
        bool _isTrader
    ) internal virtual returns (uint256 openVaultSharePrice);

    /// Helpers ///

    /// @dev Calculates the normalized time remaining of a position.
    /// @param _maturityTime The maturity time of the position.
    /// @return timeRemaining The normalized time remaining (in [0, 1]).
    function _calculateTimeRemaining(
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        uint256 latestCheckpoint = _latestCheckpoint();
        timeRemaining = _maturityTime > latestCheckpoint
            ? _maturityTime - latestCheckpoint
            : 0;

        // NOTE: Round down to underestimate the time remaining.
        timeRemaining = timeRemaining.divDown(_positionDuration);
    }

    /// @dev Calculates the normalized time remaining of a position when the
    ///      maturity time is scaled up 18 decimals.
    /// @param _maturityTime The maturity time of the position.
    function _calculateTimeRemainingScaled(
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        uint256 latestCheckpoint = _latestCheckpoint() * ONE;
        timeRemaining = _maturityTime > latestCheckpoint
            ? _maturityTime - latestCheckpoint
            : 0;

        // NOTE: Round down to underestimate the time remaining.
        timeRemaining = timeRemaining.divDown(_positionDuration * ONE);
    }

    /// @dev Gets the most recent checkpoint time.
    /// @return latestCheckpoint The latest checkpoint.
    function _latestCheckpoint()
        internal
        view
        returns (uint256 latestCheckpoint)
    {
        latestCheckpoint = HyperdriveMath.calculateCheckpointTime(
            block.timestamp,
            _checkpointDuration
        );
    }

    /// @dev Gets the effective share reserves.
    /// @return The effective share reserves. This is the share reserves used
    ///         by the YieldSpace pricing model.
    function _effectiveShareReserves() internal view returns (uint256) {
        return
            HyperdriveMath.calculateEffectiveShareReserves(
                _marketState.shareReserves,
                _marketState.shareAdjustment
            );
    }

    /// @dev Gets the amount of non-netted longs with a given maturity.
    /// @param _maturityTime The maturity time of the longs.
    /// @return The amount of non-netted longs. This is a signed value that
    ///         can be negative. This is convenient for updating the long
    ///         exposure when closing positions.
    function _nonNettedLongs(
        uint256 _maturityTime
    ) internal view returns (int256) {
        // The amount of non-netted longs is the difference between the amount
        // of longs and the amount of shorts with a given maturity time. If the
        // difference is negative, the amount of non-netted longs is zero.
        return
            _totalSupply[
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _maturityTime)
            ].toInt256() -
            _totalSupply[
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    _maturityTime
                )
            ].toInt256();
    }

    /// @dev Gets the distribute excess idle parameters from the current state.
    /// @param _vaultSharePrice The current vault share price.
    /// @return params The distribute excess idle parameters.
    /// @return success A failure flag indicating if the calculation succeeded.
    function _getDistributeExcessIdleParamsSafe(
        uint256 _idle,
        uint256 _withdrawalSharesTotalSupply,
        uint256 _vaultSharePrice
    )
        internal
        view
        returns (LPMath.DistributeExcessIdleParams memory params, bool success)
    {
        // Calculate the starting present value. If this fails, we return a
        // failure flag and proceed to avoid impacting checkpointing liveness.
        LPMath.PresentValueParams
            memory presentValueParams = _getPresentValueParams(
                _vaultSharePrice
            );
        uint256 startingPresentValue;
        (startingPresentValue, success) = LPMath.calculatePresentValueSafe(
            presentValueParams
        );
        if (!success) {
            return (params, false);
        }

        // NOTE: For consistency with the present value calculation, we round
        // up the long side and round down the short side.
        int256 netCurveTrade = presentValueParams
            .longsOutstanding
            .mulUp(presentValueParams.longAverageTimeRemaining)
            .toInt256() -
            presentValueParams
                .shortsOutstanding
                .mulDown(presentValueParams.shortAverageTimeRemaining)
                .toInt256();
        params = LPMath.DistributeExcessIdleParams({
            presentValueParams: presentValueParams,
            startingPresentValue: startingPresentValue,
            activeLpTotalSupply: _totalSupply[AssetId._LP_ASSET_ID],
            withdrawalSharesTotalSupply: _withdrawalSharesTotalSupply,
            idle: _idle,
            netCurveTrade: netCurveTrade,
            originalShareReserves: presentValueParams.shareReserves,
            originalShareAdjustment: presentValueParams.shareAdjustment,
            originalBondReserves: presentValueParams.bondReserves
        });
        success = true;
    }

    /// @dev Gets the present value parameters from the current state.
    /// @param _vaultSharePrice The current vault share price.
    /// @return params The present value parameters.
    function _getPresentValueParams(
        uint256 _vaultSharePrice
    ) internal view returns (LPMath.PresentValueParams memory params) {
        params = LPMath.PresentValueParams({
            shareReserves: _marketState.shareReserves,
            shareAdjustment: _marketState.shareAdjustment,
            bondReserves: _marketState.bondReserves,
            vaultSharePrice: _vaultSharePrice,
            initialVaultSharePrice: _initialVaultSharePrice,
            minimumShareReserves: _minimumShareReserves,
            minimumTransactionAmount: _minimumTransactionAmount,
            timeStretch: _timeStretch,
            longsOutstanding: _marketState.longsOutstanding,
            longAverageTimeRemaining: _calculateTimeRemainingScaled(
                _marketState.longAverageMaturityTime
            ),
            shortsOutstanding: _marketState.shortsOutstanding,
            shortAverageTimeRemaining: _calculateTimeRemainingScaled(
                _marketState.shortAverageMaturityTime
            )
        });
    }

    /// @dev Checks if any of the bonds the trader purchased on the curve
    ///      were purchased above the price of 1 base per bonds.
    /// @param _shareCurveDelta The amount of shares the trader pays the curve.
    /// @param _bondCurveDelta The amount of bonds the trader receives from the
    ///        curve.
    /// @param _maxSpotPrice The maximum allowable spot price for the trade.
    /// @return A flag indicating whether the trade was negative interest.
    function _isNegativeInterest(
        uint256 _shareCurveDelta,
        uint256 _bondCurveDelta,
        uint256 _maxSpotPrice
    ) internal view returns (bool) {
        // Calculate the spot price after making the trade on the curve but
        // before accounting for fees. Compare this to the max spot price to
        // determine if the trade is negative interest.
        uint256 endingSpotPrice = HyperdriveMath.calculateSpotPrice(
            _effectiveShareReserves() + _shareCurveDelta,
            _marketState.bondReserves - _bondCurveDelta,
            _initialVaultSharePrice,
            _timeStretch
        );
        return endingSpotPrice > _maxSpotPrice;
    }

    /// @dev Check solvency by verifying that the share reserves are greater
    ///      than the exposure plus the minimum share reserves.
    /// @param _vaultSharePrice The current vault share price.
    /// @return True if the share reserves are greater than the exposure plus
    ///         the minimum share reserves.
    function _isSolvent(uint256 _vaultSharePrice) internal view returns (bool) {
        // NOTE: Round the lhs down and the rhs up to make the check more
        // conservative.
        return
            uint256(_marketState.shareReserves).mulDown(_vaultSharePrice) >=
            _marketState.longExposure +
                _minimumShareReserves.mulUp(_vaultSharePrice);
    }

    /// @dev Updates the global long exposure.
    /// @param _before The checkpoint long exposure before the update.
    /// @param _after The checkpoint long exposure after the update.
    function _updateLongExposure(int256 _before, int256 _after) internal {
        _marketState.longExposure = LPMath
            .calculateLongExposure(_marketState.longExposure, _before, _after)
            .toUint128();
    }

    /// @dev Update the weighted spot price from a specified checkpoint. The
    ///      weighted spot price is a time weighted average of the spot prices
    ///      in the checkpoint.
    /// @param _checkpointTime The checkpoint time of the checkpoint to update.
    /// @param _updateTime The time at which the update is being processed. Most
    ///        of the time, this is the latest block time, but when updating
    ///        past checkpoints, this may be the time at the end of the
    ///        checkpoint.
    /// @param _spotPrice The spot price to accumulate into the time weighted
    ///        average.
    function _updateWeightedSpotPrice(
        uint256 _checkpointTime,
        uint256 _updateTime,
        uint256 _spotPrice
    ) internal {
        // If the update time is equal to the last update time, the time delta
        // is zero, so we don't need to update the time weighted average.
        uint256 lastWeightedSpotPriceUpdateTime = _checkpoints[_checkpointTime]
            .lastWeightedSpotPriceUpdateTime;
        if (_updateTime == lastWeightedSpotPriceUpdateTime) {
            return;
        }

        // If the previous weighted spot price is zero, then the weighted spot
        // price is set to the spot price that is being accumulated.
        uint256 previousWeightedSpotPrice = _checkpoints[_checkpointTime]
            .weightedSpotPrice;
        if (previousWeightedSpotPrice == 0) {
            _checkpoints[_checkpointTime].weightedSpotPrice = _spotPrice
                .toUint128();
        }
        // Otherwise the previous weighted spot price is non-zero and the update
        // time is greater than the latest update time, the we accumulate the
        // spot price into the weighted spot price.
        else {
            _checkpoints[_checkpointTime]
                .weightedSpotPrice = previousWeightedSpotPrice
                .updateWeightedAverage(
                    (lastWeightedSpotPriceUpdateTime - _checkpointTime) * ONE,
                    _spotPrice,
                    (_updateTime - lastWeightedSpotPriceUpdateTime) * ONE,
                    true
                )
                .toUint128();
        }

        // Record the update time as the last update time.
        _checkpoints[_checkpointTime]
            .lastWeightedSpotPriceUpdateTime = _updateTime.toUint128();
    }

    /// @dev Apply the updates to the market state as a result of closing a
    ///      position after maturity. This function also adjusts the proceeds
    ///      to account for any negative interest that has accrued in the
    ///      zombie reserves.
    /// @param _shareProceeds The share proceeds.
    /// @param _vaultSharePrice The current vault share price.
    /// @return The adjusted share proceeds.
    function _applyZombieClose(
        uint256 _shareProceeds,
        uint256 _vaultSharePrice
    ) internal returns (uint256) {
        // Collect any zombie interest that has accrued since the last
        // collection.
        (
            uint256 zombieBaseProceeds,
            uint256 zombieBaseReserves
        ) = _collectZombieInterest(_vaultSharePrice);

        // NOTE: Round down to underestimate the proceeds.
        //
        // If negative interest has accrued in the zombie reserves, we
        // discount the share proceeds in proportion to the amount of
        // negative interest that has accrued.
        uint256 baseProceeds = _shareProceeds.mulDown(_vaultSharePrice);
        if (zombieBaseProceeds > zombieBaseReserves) {
            _shareProceeds = _shareProceeds.mulDivDown(
                zombieBaseReserves,
                zombieBaseProceeds
            );
        }

        // Apply the updates to the zombie base proceeds and share reserves.
        if (baseProceeds < zombieBaseProceeds) {
            unchecked {
                zombieBaseProceeds -= baseProceeds;
            }
        } else {
            zombieBaseProceeds = 0;
        }
        _marketState.zombieBaseProceeds = zombieBaseProceeds.toUint112();
        uint256 zombieShareReserves = _marketState.zombieShareReserves;
        if (_shareProceeds < zombieShareReserves) {
            unchecked {
                zombieShareReserves -= _shareProceeds;
            }
        } else {
            zombieShareReserves = 0;
        }
        _marketState.zombieShareReserves = zombieShareReserves.toUint128();

        return _shareProceeds;
    }

    /// @dev Collect the interest earned on unredeemed matured positions. This
    ///      interest is split between the LPs and governance.
    /// @param _vaultSharePrice The current vault share price.
    /// @return zombieBaseProceeds The base proceeds reserved for zombie
    ///         positions.
    /// @return zombieBaseReserves The updated base reserves reserved for zombie
    ///         positions.
    function _collectZombieInterest(
        uint256 _vaultSharePrice
    )
        internal
        returns (uint256 zombieBaseProceeds, uint256 zombieBaseReserves)
    {
        // NOTE: Round down to underestimate the proceeds.
        //
        // Get the zombie base proceeds and reserves.
        zombieBaseReserves = _vaultSharePrice.mulDown(
            _marketState.zombieShareReserves
        );
        zombieBaseProceeds = _marketState.zombieBaseProceeds;

        // If the zombie base reserves are greater than the zombie base
        // proceeds, then there is interest to collect.
        if (zombieBaseReserves > zombieBaseProceeds) {
            // The interest collected on the zombie position is simply the
            // difference between the base reserves and the base proceeds.
            uint256 zombieInterest = zombieBaseReserves - zombieBaseProceeds;

            // NOTE: Round up to overestimate the impact that removing the
            // interest had on the zombie share reserves.
            //
            // Remove the zombie interest from the zombie share reserves.
            _marketState.zombieShareReserves -= zombieInterest
                .divUp(_vaultSharePrice)
                .toUint128();

            // NOTE: Round down to underestimate the zombie interest given to
            // the LPs and governance.
            //
            // Calculate and collect the governance fee.
            // The fee is calculated in terms of shares and paid to
            // governance.
            uint256 zombieInterestShares = zombieInterest.divDown(
                _vaultSharePrice
            );
            uint256 governanceZombieFeeCollected = zombieInterestShares.mulDown(
                _governanceZombieFee
            );
            _governanceFeesAccrued += governanceZombieFeeCollected;

            // The zombie interest that was collected (minus the fees paid to
            // governance), are reinvested in the share reserves. The share
            // adjustment is updated in lock-step to avoid changing the curve's
            // k invariant.
            zombieInterestShares -= governanceZombieFeeCollected;
            _marketState.shareReserves += zombieInterestShares.toUint128();
            _marketState.shareAdjustment += zombieInterestShares.toInt128();

            // After collecting the interest, the zombie base reserves are
            // equal to the zombie base proceeds.
            zombieBaseReserves = zombieBaseProceeds;
        }
    }

    /// @dev Calculates the number of share reserves that are not reserved by
    ///      open positions.
    /// @param _vaultSharePrice The current vault share price.
    /// @return idleShares The amount of shares that are available for LPs to
    ///         withdraw.
    function _calculateIdleShareReserves(
        uint256 _vaultSharePrice
    ) internal view returns (uint256 idleShares) {
        // NOTE: Round up to underestimate the pool's idle.
        uint256 longExposure = uint256(_marketState.longExposure).divUp(
            _vaultSharePrice
        );
        if (_marketState.shareReserves > longExposure + _minimumShareReserves) {
            idleShares =
                _marketState.shareReserves -
                longExposure -
                _minimumShareReserves;
        }
        return idleShares;
    }

    /// @dev Calculates the LP share price. If the LP share price can't be
    ///      calculated, this function returns a failure flag.
    /// @param _vaultSharePrice The current vault share price.
    /// @return The LP share price in units of (base / lp shares).
    /// @return A flag indicating if the calculation succeeded.
    function _calculateLPSharePriceSafe(
        uint256 _vaultSharePrice
    ) internal view returns (uint256, bool) {
        // Calculate the present value safely to prevent liveness problems. If
        // the calculation fails, we return 0.
        (uint256 presentValueShares, bool success) = LPMath
            .calculatePresentValueSafe(
                _getPresentValueParams(_vaultSharePrice)
            );
        if (!success) {
            return (0, false);
        }

        // Calculate the LP total supply.
        uint256 lpTotalSupply = _totalSupply[AssetId._LP_ASSET_ID] +
            _totalSupply[AssetId._WITHDRAWAL_SHARE_ASSET_ID] -
            _withdrawPool.readyToWithdraw;

        // If the LP total supply is zero, the LP share price can't be computed
        // due to a divide-by-zero error.
        if (lpTotalSupply == 0) {
            return (0, false);
        }

        // NOTE: Round down to underestimate the LP share price.
        //
        // Calculate the LP share price.
        uint256 lpSharePrice = _vaultSharePrice > 0
            ? presentValueShares.mulDivDown(_vaultSharePrice, lpTotalSupply)
            : 0;

        return (lpSharePrice, true);
    }

    /// @dev Calculates the pool's solvency if a long is opened that brings the
    ///      rate to 0%. This is the maximum possible long that can be opened on
    ///      the YieldSpace curve.
    /// @param _shareReserves The pool's share reserves.
    /// @param _shareAdjustment The pool's share adjustment.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _vaultSharePrice The vault share price.
    /// @param _longExposure The pool's long exposure.
    /// @param _checkpointExposure The pool's checkpoint exposure.
    /// @return The solvency after opening the max long.
    /// @return A flag indicating whether or not the calculation succeeded.
    function _calculateSolvencyAfterMaxLongSafe(
        uint256 _shareReserves,
        int256 _shareAdjustment,
        uint256 _bondReserves,
        uint256 _vaultSharePrice,
        uint256 _longExposure,
        int256 _checkpointExposure
    ) internal view returns (int256, bool) {
        // Calculate the share payment and bond proceeds of opening the largest
        // possible long on the YieldSpace curve. This does not include fees.
        // These calculations fail when the max long is close to zero, and we
        // ignore these failures since we can proceed with the calculation in
        // this case.
        (uint256 effectiveShareReserves, bool success) = HyperdriveMath
            .calculateEffectiveShareReservesSafe(
                _shareReserves,
                _shareAdjustment
            );
        if (!success) {
            return (0, false);
        }
        (uint256 maxSharePayment, ) = YieldSpaceMath
            .calculateMaxBuySharesInSafe(
                effectiveShareReserves,
                _bondReserves,
                ONE - _timeStretch,
                _vaultSharePrice,
                _initialVaultSharePrice
            );
        (uint256 maxBondProceeds, ) = YieldSpaceMath
            .calculateBondsOutGivenSharesInDownSafe(
                effectiveShareReserves,
                _bondReserves,
                maxSharePayment,
                ONE - _timeStretch,
                _vaultSharePrice,
                _initialVaultSharePrice
            );

        // If one of the max share payment or max bond proceeds calculations
        // fail or return zero, the max long amount is zero plus or minus a few
        // wei.
        if (maxSharePayment == 0 || maxBondProceeds == 0) {
            maxSharePayment = 0;
            maxBondProceeds = 0;
        }

        // Apply the fees from opening a long to the max share payment and bond
        // proceeds. Fees applied to the share payment hurt solvency and fees
        // applied to the bond proceeds make the pool more solvent. To be
        // conservative, we only apply the fee to the share payment.
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            effectiveShareReserves,
            _bondReserves,
            _initialVaultSharePrice,
            _timeStretch
        );
        (maxSharePayment, , ) = _calculateOpenLongFees(
            maxSharePayment,
            maxBondProceeds,
            _vaultSharePrice,
            spotPrice
        );

        // Calculate the pool's solvency after opening the max long.
        uint256 shareReserves = _shareReserves + maxSharePayment;
        uint256 longExposure = LPMath.calculateLongExposure(
            _longExposure,
            _checkpointExposure,
            _checkpointExposure + maxBondProceeds.toInt256()
        );
        uint256 vaultSharePrice = _vaultSharePrice;
        return (
            shareReserves.mulDown(vaultSharePrice).toInt256() -
                longExposure.toInt256() -
                _minimumShareReserves.mulUp(vaultSharePrice).toInt256(),
            true
        );
    }

    /// @dev Calculates the share reserves delta, the bond reserves delta, and
    ///      the total governance fee after opening a long.
    /// @param _shareReservesDelta The change in the share reserves without fees.
    /// @param _bondReservesDelta The change in the bond reserves without fees.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _spotPrice The current spot price.
    /// @return The change in the share reserves with fees.
    /// @return The change in the bond reserves with fees.
    /// @return The governance fee in shares.
    function _calculateOpenLongFees(
        uint256 _shareReservesDelta,
        uint256 _bondReservesDelta,
        uint256 _vaultSharePrice,
        uint256 _spotPrice
    ) internal view returns (uint256, uint256, uint256) {
        // Calculate the fees charged to the user (curveFee) and the portion
        // of those fees that are paid to governance (governanceCurveFee).
        (
            uint256 curveFee, // bonds
            uint256 governanceCurveFee // bonds
        ) = _calculateFeesGivenShares(
                _shareReservesDelta,
                _spotPrice,
                _vaultSharePrice
            );

        // Calculate the impact of the curve fee on the bond reserves. The curve
        // fee benefits the LPs by causing less bonds to be deducted from the
        // bond reserves.
        _bondReservesDelta -= curveFee;

        // NOTE: Round down to underestimate the governance fee.
        //
        // Calculate the fees owed to governance in shares. Open longs are
        // calculated entirely on the curve so the curve fee is the total
        // governance fee. In order to convert it to shares we need to multiply
        // it by the spot price and divide it by the vault share price:
        //
        // shares = (bonds * base/bonds) / (base/shares)
        // shares = bonds * shares/bonds
        // shares = shares
        uint256 totalGovernanceFee = governanceCurveFee.mulDivDown(
            _spotPrice,
            _vaultSharePrice
        );

        // Calculate the number of shares to add to the shareReserves.
        // shareReservesDelta, _shareAmount and totalGovernanceFee
        // are all denominated in shares:
        //
        // shares = shares - shares
        _shareReservesDelta -= totalGovernanceFee;

        return (_shareReservesDelta, _bondReservesDelta, totalGovernanceFee);
    }

    /// @dev Calculates the fees that go to the LPs and governance.
    /// @param _shareAmount The amount of shares exchanged for bonds.
    /// @param _spotPrice The price without slippage of bonds in terms of base
    ///         (base/bonds).
    /// @param _vaultSharePrice The current vault share price (base/shares).
    /// @return curveFee The curve fee. The fee is in terms of bonds.
    /// @return governanceCurveFee The curve fee that goes to governance. The
    ///         fee is in terms of bonds.
    function _calculateFeesGivenShares(
        uint256 _shareAmount,
        uint256 _spotPrice,
        uint256 _vaultSharePrice
    ) internal view returns (uint256 curveFee, uint256 governanceCurveFee) {
        // NOTE: Round up to overestimate the curve fee.
        //
        // Fixed Rate (r) = (value at maturity - purchase price)/(purchase price)
        //                = (1-p)/p
        //                = ((1 / p) - 1)
        //                = the ROI at maturity of a bond purchased at price p
        //
        // Another way to think about it:
        //
        // p (spot price) tells us how many base a bond is worth -> p = base/bonds
        // 1/p tells us how many bonds a base is worth -> 1/p = bonds/base
        // 1/p - 1 tells us how many additional bonds we get for each
        // base -> (1/p - 1) = additional bonds/base
        //
        // The curve fee is taken from the additional bonds the user gets for
        // each base:
        //
        // curve fee = ((1 / p) - 1) * phi_curve * c * dz
        //           = r * phi_curve * base/shares * shares
        //           = bonds/base * phi_curve * base
        //           = bonds * phi_curve
        curveFee = (ONE.divUp(_spotPrice) - ONE)
            .mulUp(_curveFee)
            .mulUp(_vaultSharePrice)
            .mulUp(_shareAmount);

        // NOTE: Round down to underestimate the governance curve fee.
        //
        // We leave the governance fee in terms of bonds:
        // governanceCurveFee = curve_fee * phi_gov
        //                    = bonds * phi_gov
        governanceCurveFee = curveFee.mulDown(_governanceLPFee);
    }

    /// @dev Calculates the fees that go to the LPs and governance.
    /// @param _bondAmount The amount of bonds being exchanged for shares.
    /// @param _normalizedTimeRemaining The normalized amount of time until
    ///        maturity.
    /// @param _spotPrice The price without slippage of bonds in terms of base
    ///        (base/bonds).
    /// @param _vaultSharePrice The current vault share price (base/shares).
    /// @return curveFee The curve fee. The fee is in terms of shares.
    /// @return flatFee The flat fee. The fee is in terms of shares.
    /// @return governanceCurveFee The curve fee that goes to governance. The
    ///         fee is in terms of shares.
    /// @return totalGovernanceFee The total fee that goes to governance. The
    ///         fee is in terms of shares.
    function _calculateFeesGivenBonds(
        uint256 _bondAmount,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _vaultSharePrice
    )
        internal
        view
        returns (
            uint256 curveFee,
            uint256 flatFee,
            uint256 governanceCurveFee,
            uint256 totalGovernanceFee
        )
    {
        // NOTE: Round up to overestimate the curve fee.
        //
        // p (spot price) tells us how many base a bond is worth -> p = base/bonds
        // 1 - p tells us how many additional base a bond is worth at
        // maturity -> (1 - p) = additional base/bonds
        //
        // The curve fee is taken from the additional base the user gets for
        // each bond at maturity:
        //
        // curve fee = ((1 - p) * phi_curve * d_y * t)/c
        //           = (base/bonds * phi_curve * bonds * t) / (base/shares)
        //           = (base/bonds * phi_curve * bonds * t) * (shares/base)
        //           = (base * phi_curve * t) * (shares/base)
        //           = phi_curve * t * shares
        curveFee = _curveFee
            .mulUp(ONE - _spotPrice)
            .mulUp(_bondAmount)
            .mulDivUp(_normalizedTimeRemaining, _vaultSharePrice);

        // NOTE: Round down to underestimate the governance curve fee.
        //
        // Calculate the curve portion of the governance fee:
        //
        // governanceCurveFee = curve_fee * phi_gov
        //                    = shares * phi_gov
        governanceCurveFee = curveFee.mulDown(_governanceLPFee);

        // NOTE: Round up to overestimate the flat fee.
        //
        // The flat portion of the fee is taken from the matured bonds.
        // Since a matured bond is worth 1 base, it is appropriate to consider
        // d_y in units of base:
        //
        // flat fee = (d_y * (1 - t) * phi_flat) / c
        //          = (base * (1 - t) * phi_flat) / (base/shares)
        //          = (base * (1 - t) * phi_flat) * (shares/base)
        //          = shares * (1 - t) * phi_flat
        uint256 flat = _bondAmount.mulDivUp(
            ONE - _normalizedTimeRemaining,
            _vaultSharePrice
        );
        flatFee = flat.mulUp(_flatFee);

        // NOTE: Round down to underestimate the total governance fee.
        //
        // We calculate the flat portion of the governance fee as:
        //
        // governance_flat_fee = flat_fee * phi_gov
        //                     = shares * phi_gov
        //
        // The totalGovernanceFee is the sum of the curve and flat governance fees.
        totalGovernanceFee =
            governanceCurveFee +
            flatFee.mulDown(_governanceLPFee);
    }

    /// @dev Converts input to what is specified in the options from base.
    /// @param _amount The amount to convert.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _options The options that configure the conversion.
    /// @return The converted amount.
    function _convertToOptionFromBase(
        uint256 _amount,
        uint256 _vaultSharePrice,
        IHyperdrive.Options calldata _options
    ) internal pure returns (uint256) {
        if (_options.asBase) {
            return _amount;
        } else {
            // NOTE: Round down to underestimate the shares amount.
            return _amount.divDown(_vaultSharePrice);
        }
    }
}
