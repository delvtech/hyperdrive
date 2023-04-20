// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { Errors } from "./libraries/Errors.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";

/// @author DELV
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
        if (marketState.isInitialized) {
            revert Errors.PoolAlreadyInitialized();
        }

        // Deposit for the user, this transfers from them.
        (uint256 shares, uint256 sharePrice) = _deposit(
            _contribution,
            _asUnderlying
        );

        // Create an initial checkpoint.
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Set the initialized state to true.
        marketState.isInitialized = true;

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

        // FIXME: Can the LP total supply ever dip to zero and then go back up?
        // Think more about this. If it shouldn't be possible, then we should
        // have a strict error that prohibits this.
        //
        // In the case that there are existing LP shares, we calculate the
        // amount of LP shares to mint as a function of the present value in
        // the pool controlled by LPs. This ensures that LPs are fairly rewarded
        // for adding liquidity. Otherwise, we mint the full amount of LP shares.
        //
        // TODO: We should have a constant for the withdrawal shares asset ID if we're not going to tranche.
        uint256 lpTotalSupply = totalSupply[AssetId._LP_ASSET_ID] +
            totalSupply[
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
            ] -
            withdrawPool.readyToWithdraw;
        if (lpTotalSupply > 0) {
            // Calculate the present value before updating the reserves.
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: marketState.shareReserves,
                    bondReserves: marketState.bondReserves,
                    sharePrice: sharePrice,
                    initialSharePrice: initialSharePrice,
                    timeStretch: timeStretch,
                    longsOutstanding: marketState.longsOutstanding,
                    longAverageTimeRemaining: _calculateTimeRemaining(
                        uint256(longAggregates.averageMaturityTime).divUp(1e36) // scale to seconds
                    ),
                    longBaseVolume: longAggregates.baseVolume, // TODO: This isn't used.
                    shortsOutstanding: marketState.shortsOutstanding,
                    shortAverageTimeRemaining: _calculateTimeRemaining(
                        uint256(shortAggregates.averageMaturityTime).divUp(1e36) // scale to seconds
                    ),
                    shortBaseVolume: shortAggregates.baseVolume
                });
            uint256 startingPresentValue = HyperdriveMath.calculatePresentValue(
                params
            );

            // TODO: If we start caching state changes in memory (which would
            // be preferable), then we could bundle all of this into a single
            // calculation in HyperdriveMath.
            //
            // Add the liquidity to the pool's reserves and calculate the new
            // present value.
            _updateLiquidity(int256(shares));
            params.shareReserves = marketState.shareReserves;
            params.bondReserves = marketState.bondReserves;
            uint256 endingPresentValue = HyperdriveMath.calculatePresentValue(
                params
            );

            // The LP shares minted to the LP is derived by solving for the
            // change in LP shares that preserves the ratio of present value to
            // total LP shares. This is given by:
            //
            // PV0 / l0 = PV1 / (l0 + dl) => dl = ((PV1 - PV0) * l0) / PV0
            lpShares = (endingPresentValue - startingPresentValue).mulDivDown(
                lpTotalSupply,
                startingPresentValue
            );
        } else {
            // FIXME: See if making the initialize flow consistent with this
            // fixes the current problem.
            //
            // TODO: Explain why we do this instead of minting the amount
            //       of LP shares used on initialization.
            //
            // If there are no LP shares, we mint them 1:1 with
            lpShares = shares;

            // Add the liquidity to the pool's reserves.
            _updateLiquidity(int256(shares));
        }

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
    ) external returns (uint256, uint256) {
        if (_shares == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint.
        uint256 sharePrice = _pricePerShare();
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Burn the LP shares.
        uint256 activeLpTotalSupply = totalSupply[AssetId._LP_ASSET_ID];
        uint256 lpTotalSupply = activeLpTotalSupply +
            totalSupply[
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
            ] -
            withdrawPool.readyToWithdraw;
        _burn(AssetId._LP_ASSET_ID, msg.sender, _shares);

        // Calculate the starting present value of the pool.
        HyperdriveMath.PresentValueParams memory params = HyperdriveMath
            .PresentValueParams({
                shareReserves: marketState.shareReserves,
                bondReserves: marketState.bondReserves,
                sharePrice: sharePrice,
                initialSharePrice: initialSharePrice,
                timeStretch: timeStretch,
                longsOutstanding: marketState.longsOutstanding,
                longAverageTimeRemaining: _calculateTimeRemaining(
                    uint256(longAggregates.averageMaturityTime).divUp(1e36) // scale to seconds
                ),
                longBaseVolume: longAggregates.baseVolume, // TODO: This isn't used.
                shortsOutstanding: marketState.shortsOutstanding,
                shortAverageTimeRemaining: _calculateTimeRemaining(
                    uint256(shortAggregates.averageMaturityTime).divUp(1e36) // scale to seconds
                ),
                shortBaseVolume: shortAggregates.baseVolume
            });
        uint256 startingPresentValue = HyperdriveMath.calculatePresentValue(
            params
        );

        // The LP is given their share of the idle capital in the pool. This
        // is removed from the pool's reserves and paid out immediately. The
        // idle amount is given by:
        //
        // idle = (z - (o_l / c)) * (dl / l_a)
        uint256 shareProceeds = (marketState.shareReserves -
            uint256(marketState.longsOutstanding).divDown(params.sharePrice))
            .mulDivDown(_shares, activeLpTotalSupply);
        _updateLiquidity(-int256(shareProceeds));
        params.shareReserves = marketState.shareReserves;
        params.bondReserves = marketState.bondReserves;
        uint256 endingPresentValue = HyperdriveMath.calculatePresentValue(
            params
        );

        // Calculate the amount of withdrawal shares that should be minted. We
        // solve for this value by solving the present value equation as
        // follows:
        //
        // PV0 / l0 = PV1 / (l0 - dl + dw) => dw = (PV1 / PV0) * l0 - (l0 - dl)
        uint256 withdrawalShares = lpTotalSupply.mulDivDown(
            endingPresentValue,
            startingPresentValue
        );
        withdrawalShares -= lpTotalSupply - _shares;
        // TODO: This is a hack to avoid a numerical error that results in
        // stuck LP tokens. We need to stress test the system to see if this
        // is adequate protection.
        withdrawalShares = withdrawalShares < 1e4 ? 0 : withdrawalShares;

        // Mint the withdrawal shares to the LP.
        _mint(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0),
            _destination,
            withdrawalShares
        );

        // Withdraw the shares from the yield source.
        (uint256 baseProceeds, ) = _withdraw(
            shareProceeds,
            _destination,
            _asUnderlying
        );

        // Enforce min user outputs
        if (_minOutput > baseProceeds) revert Errors.OutputLimit();

        return (baseProceeds, withdrawalShares);
    }

    /// @notice Redeems withdrawal shares by giving the LP a pro-rata amount of
    ///         the withdrawal pool's proceeds. This function redeems the
    ///         maximum amount of the specified withdrawal shares given the
    ///         amount of withdrawal shares ready to withdraw.
    /// @param _shares The withdrawal shares to redeem.
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

        // Clamp the shares to the total amount of shares ready for withdrawal
        // to avoid unnecessary reverts.
        _shares = _shares <= withdrawPool.readyToWithdraw
            ? _shares
            : withdrawPool.readyToWithdraw;

        // We burn the shares from the user
        _burn(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0),
            msg.sender,
            _shares
        );

        // The LP gets the pro-rata amount of the collected proceeds.
        uint256 proceeds = _shares.mulDivDown(
            uint128(withdrawPool.proceeds),
            uint128(withdrawPool.readyToWithdraw)
        );

        // Apply the update to the withdrawal pool.
        withdrawPool.readyToWithdraw -= uint128(_shares);
        withdrawPool.proceeds -= uint128(proceeds);

        // Withdraw for the user
        (_proceeds, ) = _withdraw(proceeds, _destination, _asUnderlying);

        // Enforce min user outputs
        if (_minOutput > _proceeds) revert Errors.OutputLimit();
    }

    /// @dev Updates the pool's liquidity and holds the pool's APR constant.
    /// @param _shareReservesDelta The delta that should be applied to share reserves.
    function _updateLiquidity(int256 _shareReservesDelta) internal {
        // TODO: We need to stress test the assumption that the pool's share
        // reserves will only be equal to zero in the narrow case outlined
        // below.
        //
        // If the share reserves delta is equal to zero, there is no need to
        // update the reserves. If the share reserves are equal to zero, the
        // APR is undefined and the reserves cannot be updated. This only occurs
        // when all of the liquidity has been removed from the pool and the
        // only remaining positions are shorts. Otherwise, we update the pool
        // by increasing the share reserves and preserving the previous ratio of
        // share reserves to bond reserves.
        uint256 shareReserves = marketState.shareReserves;
        if (_shareReservesDelta != 0 && shareReserves > 0) {
            int256 updatedShareReserves = int256(shareReserves) +
                _shareReservesDelta;
            marketState.shareReserves = uint256(
                // TODO: This seems to be masking a numerical problem. This
                // should be investigated more.
                //
                // NOTE: There is a 1 wei discrepancy in some of the
                // calculations which results in this clamping being required.
                updatedShareReserves >= 0 ? updatedShareReserves : int256(0)
            ).toUint128();
            marketState.bondReserves = uint256(marketState.bondReserves)
                .mulDivDown(marketState.shareReserves, shareReserves)
                .toUint128();
        }
    }

    /// @dev Pays out the maximum amount of withdrawal shares given a specified
    ///      amount of withdrawal proceeds.
    /// @param _withdrawalProceeds The amount of withdrawal proceeds to pay out.
    /// @param _withdrawalSharesOutstanding The amount of withdrawal shares
    ///        that haven't been paid out.
    /// @param _sharePrice The current share price.
    function _applyWithdrawalProceeds(
        uint256 _withdrawalProceeds,
        uint256 _withdrawalSharesOutstanding,
        uint256 _sharePrice
    ) internal {
        // Calculate the maximum amount of LP shares that could be paid out by
        // the withdrawal proceeds. The calculation uses the ratio of present
        // value to LP total supply as follows:
        //
        // maxSharesReleased = withdrawalProceeds * (l / PV)
        //
        // In the event that all of the LPs have removed their liquidity and the
        // remaining positions hit maturity, all of the withdrawal shares are
        // marked as ready to withdraw.
        uint256 presentValue = HyperdriveMath.calculatePresentValue(
            HyperdriveMath.PresentValueParams({
                shareReserves: marketState.shareReserves,
                bondReserves: marketState.bondReserves,
                sharePrice: _sharePrice,
                initialSharePrice: initialSharePrice,
                timeStretch: timeStretch,
                longsOutstanding: marketState.longsOutstanding,
                longAverageTimeRemaining: _calculateTimeRemaining(
                    uint256(longAggregates.averageMaturityTime).divUp(1e36) // scale to seconds
                ),
                longBaseVolume: longAggregates.baseVolume, // TODO: This isn't used.
                shortsOutstanding: marketState.shortsOutstanding,
                shortAverageTimeRemaining: _calculateTimeRemaining(
                    uint256(shortAggregates.averageMaturityTime).divUp(1e36) // scale to seconds
                ),
                shortBaseVolume: shortAggregates.baseVolume
            })
        );
        uint256 lpTotalSupply = totalSupply[AssetId._LP_ASSET_ID] +
            _withdrawalSharesOutstanding;
        uint256 maxSharesReleased = presentValue > 0
            ? _withdrawalProceeds.mulDivDown(lpTotalSupply, presentValue)
            : lpTotalSupply;

        // Calculate the amount of withdrawal shares that will be released and
        // the amount of capital that will be used to pay out the withdrawal
        // pool.
        uint256 sharesReleased = maxSharesReleased <=
            _withdrawalSharesOutstanding
            ? maxSharesReleased
            : _withdrawalSharesOutstanding;
        uint256 withdrawalPoolProceeds = _withdrawalProceeds.mulDivDown(
            sharesReleased,
            maxSharesReleased
        );
        withdrawPool.readyToWithdraw += uint128(sharesReleased);
        withdrawPool.proceeds += uint128(withdrawalPoolProceeds);

        // Remove the withdrawal pool proceeds from the reserves.
        _updateLiquidity(-int256(withdrawalPoolProceeds));
    }
}
