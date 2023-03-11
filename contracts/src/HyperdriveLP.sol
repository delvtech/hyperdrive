// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { Errors } from "./libraries/Errors.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";

/// @author Delve
/// @title HyperdriveLP
/// @notice Implements the LP accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveLP is HyperdriveBase {
    using FixedPointMath for uint256;
    using SafeCast for uint256;

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of base to supply.
    /// @param _apr The target APR.
    /// @param _destination The destination of the LP shares.
    /// @param _asUnderlying If true the user is charged in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    function initialize(
        uint256 _contribution,
        uint256 _apr,
        address _destination,
        bool _asUnderlying
    ) external {
        // Ensure that the pool hasn't been initialized yet.
        if (marketState.shareReserves > 0 || marketState.bondReserves > 0) {
            revert Errors.PoolAlreadyInitialized();
        }

        // Deposit for the user, this transfers from them.
        (uint256 shares, uint256 sharePrice) = _deposit(
            _contribution,
            _asUnderlying
        );

        // Create an initial checkpoint.
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Update the reserves. The bond reserves are calculated so that the
        // pool is initialized with the target APR.
        marketState.shareReserves = shares.toUint128();
        uint256 unadjustedBondReserves = HyperdriveMath
            .calculateInitialBondReserves(
                shares,
                sharePrice,
                initialSharePrice,
                _apr,
                positionDuration,
                timeStretch
            );
        uint256 initialLpShares = unadjustedBondReserves +
            sharePrice.mulDown(shares);
        marketState.bondReserves = (unadjustedBondReserves + initialLpShares)
            .toUint128();

        // Mint LP shares to the initializer.
        // TODO - Should we index the lp share and virtual reserve to shares or to underlying?
        //        I think in the case where price per share < 1 there may be a problem.
        _mint(AssetId._LP_ASSET_ID, _destination, initialLpShares);
    }

    /// @notice Allows LPs to supply liquidity for LP shares.
    /// @param _contribution The amount of base to supply.
    /// @param _minApr The minimum APR at which the LP is willing to supply.
    /// @param _maxApr The maximum APR at which the LP is willing to supply.
    /// @param _destination The address which will hold the LP shares
    /// @param _asUnderlying If true the user is charged in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return lpShares The number of LP tokens created
    function addLiquidity(
        uint256 _contribution,
        uint256 _minApr,
        uint256 _maxApr,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256 lpShares) {
        if (_contribution == 0) {
            revert Errors.ZeroAmount();
        }

        // Enforce the slippage guard.
        uint256 apr = HyperdriveMath.calculateAPRFromReserves(
            marketState.shareReserves,
            marketState.bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        if (apr < _minApr || apr > _maxApr) revert Errors.InvalidApr();

        // Deposit for the user, this call also transfers from them
        (uint256 shares, uint256 sharePrice) = _deposit(
            _contribution,
            _asUnderlying
        );

        // Perform a checkpoint.
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // To ensure that our LP allocation scheme fairly rewards LPs for adding
        // liquidity, we linearly interpolate between the present and future
        // value of longs and shorts. These interpolated values are the long and
        // short adjustments. The following calculation is used to determine the
        // amount of LP shares rewarded to new LP:
        //
        // lpShares = (dz * l) / (z + a_s - a_l)
        uint256 longAdjustment = HyperdriveMath.calculateLpAllocationAdjustment(
            marketState.longsOutstanding,
            aggregates.longBaseVolume,
            _calculateTimeRemaining(aggregates.longAverageMaturityTime),
            sharePrice
        );
        uint256 shortAdjustment = HyperdriveMath
            .calculateLpAllocationAdjustment(
                marketState.shortsOutstanding,
                aggregates.shortBaseVolume,
                _calculateTimeRemaining(aggregates.shortAverageMaturityTime),
                sharePrice
            );
        lpShares = shares.mulDown(totalSupply[AssetId._LP_ASSET_ID]).divDown(
            uint256(marketState.shareReserves).add(shortAdjustment).sub(
                longAdjustment
            )
        );

        // Add the liquidity to the pool's reserves.
        _updateLiquidity(int256(shares));

        // Mint LP shares to the supplier.
        _mint(AssetId._LP_ASSET_ID, _destination, lpShares);
    }

    /// @notice Allows an LP to burn shares and withdraw from the pool.
    /// @param _shares The LP shares to burn.
    /// @param _minOutput The minium amount of the base token to receive.Note - this
    ///                   value is likely to be less than the amount LP shares are worth.
    ///                   The remainder is in short and long withdraw shares which are hard
    ///                   to game the value of.
    /// @param _destination The address which will receive the withdraw proceeds
    /// @param _asUnderlying If true the user is paid in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return Returns the base out, the lond withdraw shares out and the short withdraw
    ///         shares out.
    function removeLiquidity(
        uint256 _shares,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256, uint256, uint256) {
        if (_shares == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint.
        uint256 sharePrice = _pricePerShare();
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        uint256 totalSupply = totalSupply[AssetId._LP_ASSET_ID];

        // Calculate the withdrawal proceeds of the LP. This includes the base,
        // long withdrawal shares, and short withdrawal shares that the LP
        // receives.
        (
            uint256 shareProceeds,
            uint256 longWithdrawalShares,
            uint256 shortWithdrawalShares
        ) = HyperdriveMath.calculateOutForLpSharesIn(
                _shares,
                marketState.shareReserves,
                totalSupply,
                marketState.longsOutstanding,
                marketState.shortsOutstanding,
                sharePrice
            );

        // Burn the LP shares.
        _burn(AssetId._LP_ASSET_ID, msg.sender, _shares);

        // Remove the liquidity from the pool's reserves.
        _updateLiquidity(-int256(shareProceeds));

        // The withdrawing LP will get their percent of the margin which is
        // used to back open positions as a token which can be redeemed for
        // margin as it becomes available.
        uint256 userMargin = marketState.longsOutstanding -
            aggregates.longBaseVolume;
        userMargin += aggregates.shortBaseVolume;
        userMargin = userMargin.mulDivDown(_shares, totalSupply);
        // Mint the withdrawal tokens.
        _mint(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0),
            _destination,
            userMargin.divDown(sharePrice)
        );

        // Withdraw the shares from the yield source.
        (uint256 baseOutput, ) = _withdraw(
            shareProceeds,
            _destination,
            _asUnderlying
        );

        // Enforce min user outputs
        if (_minOutput > baseOutput) revert Errors.OutputLimit();

        return (baseOutput, longWithdrawalShares, shortWithdrawalShares);
    }

    /// @notice Redeems withdrawal shares if enough margin has been freed to do so.
    /// @param _shares The withdrawal shares to redeem
    /// @param _minOutput The minimum amount of base the LP expects to receive.
    /// @param _destination The address which receive the withdraw proceeds
    /// @param _asUnderlying If true the user is paid in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return _proceeds The amount of base the LP received.
    function redeemWithdrawalShares(
        uint256 _shares,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256 _proceeds) {
        // Perform a checkpoint.
        uint256 sharePrice = _pricePerShare();
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // The user gets a refund on their margin equal to the face
        // value of their withdraw shares times the percent of the withdraw
        // pool which has been lost.
        uint256 recoveredMargin = _shares.mulDivDown(
            uint128(withdrawPool.capital),
            uint128(withdrawPool.withdrawSharesReadyToWithdraw)
        );
        // The user gets interest equal to their percent of the withdraw pool
        // times the withdraw pool interest
        uint256 recoveredInterest = _shares.mulDivDown(
            uint128(withdrawPool.interest),
            uint128(withdrawPool.withdrawSharesReadyToWithdraw)
        );

        // Update the pool state
        // Note - Will revert here if not enough margin has been reclaimed by checkpoints or
        //        by position closes
        withdrawPool.withdrawSharesReadyToWithdraw -= uint128(_shares);
        withdrawPool.capital -= uint128(recoveredMargin);
        withdrawPool.interest -= uint128(recoveredInterest);

        // Withdraw for the user
        (_proceeds, ) = _withdraw(
            recoveredMargin + recoveredInterest,
            _destination,
            _asUnderlying
        );

        // Enforce min user outputs
        if (_minOutput > _proceeds) revert Errors.OutputLimit();
    }

    /// @dev Updates the pool's liquidity and holds the pool's APR constant.
    /// @param _shareReservesDelta The delta that should be applied to share reserves.
    function _updateLiquidity(int256 _shareReservesDelta) internal {
        // Apply the update to the pool's share reserves and solve for the bond
        // reserves that maintains the current pool APR.
        uint256 shareReserves = marketState.shareReserves;
        marketState.shareReserves = uint256(
            int256(shareReserves) + _shareReservesDelta
        ).toUint128();
        marketState.bondReserves = uint256(marketState.bondReserves)
            .mulDivDown(marketState.shareReserves, shareReserves)
            .toUint128();
    }

    /// @dev Moves capital into the withdraw pool and marks shares ready for withdraw.
    /// @param freedCapital The amount of capital to add to the withdraw pool, must not be more than the max capital
    /// @param maxCapital The margin which the LP used to back the position which is being closed.
    /// @param interest The interest earned by this margin position, fixed interest for LP shorts and variable for longs.
    /// @return (the capital added to the withdraw pool, the interest added to the interest pool)
    function _freeMargin(
        uint256 freedCapital,
        uint256 maxCapital,
        uint256 interest
    ) internal returns (uint256, uint256) {
        // If we don't have capital to free then simply return zero
        uint256 withdrawShareSupply = totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
        ];
        if (withdrawShareSupply <= withdrawPool.withdrawSharesReadyToWithdraw) {
            return (0, 0);
        }
        // If we have more capital freed than needed we adjust down all values
        if (
            maxCapital + uint256(withdrawPool.withdrawSharesReadyToWithdraw) >
            uint256(withdrawShareSupply)
        ) {
            // In this case we want maxCapital*adjustment + withdrawPool.withdrawSharesReadyToWithdraw = withdrawShareSupply
            // so adjustment = (withdrawShareSupply - withdrawPool.withdrawSharesReadyToWithdraw)/maxCapital
            // We adjust maxCapital and do corresponding reduction in freedCapital and interest
            uint256 adjustment = uint256(
                withdrawShareSupply - withdrawPool.withdrawSharesReadyToWithdraw
            ).divDown(maxCapital);
            freedCapital = freedCapital.mulDown(adjustment);
            interest = interest.mulDown(adjustment);
            maxCapital = maxCapital.mulDown(adjustment);
        }

        // Now we update the withdraw pool.
        withdrawPool.withdrawSharesReadyToWithdraw += maxCapital.toUint128();
        withdrawPool.capital += freedCapital.toUint128();
        withdrawPool.interest += interest.toUint128();
        // Finally return the amount used by this action and the caller can update reserves.
        return (freedCapital, interest);
    }

    /// @notice Checks if margin needs to be freed
    /// @return Returns true if margin needs to be freed
    function _needsToBeFreed() internal view returns (bool) {
        return
            totalSupply[
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
            ] > uint256(withdrawPool.withdrawSharesReadyToWithdraw);
    }
}
