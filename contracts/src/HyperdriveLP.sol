// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { SafeCast } from "./libraries/SafeCast.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { Errors } from "./libraries/Errors.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { HyperdriveTWAP } from "./HyperdriveTWAP.sol";

/// @author DELV
/// @title HyperdriveLP
/// @notice Implements the LP accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveLP is HyperdriveTWAP {
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
    ) external payable {
        // Ensure that the pool hasn't been initialized yet.
        if (_marketState.isInitialized) {
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
        _marketState.isInitialized = true;

        // Update the reserves. The bond reserves are calculated so that the
        // pool is initialized with the target APR.
        _marketState.shareReserves = shares.toUint128();
        _marketState.bondReserves = HyperdriveMath
            .calculateInitialBondReserves(
                shares,
                _initialSharePrice,
                _apr,
                _positionDuration,
                _timeStretch
            )
            .toUint128();

        // Mint LP shares to the initializer.
        _mint(AssetId._LP_ASSET_ID, _destination, shares);

        // Emit an Initialize event.
        emit Initialize(_destination, shares, _contribution, _apr);
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
    ) external payable isNotPaused returns (uint256 lpShares) {
        if (_contribution == 0) {
            revert Errors.ZeroAmount();
        }

        // Enforce the slippage guard.
        uint256 apr = HyperdriveMath.calculateAPRFromReserves(
            _marketState.shareReserves,
            _marketState.bondReserves,
            _initialSharePrice,
            _positionDuration,
            _timeStretch
        );
        if (apr < _minApr || apr > _maxApr) revert Errors.InvalidApr();

        // Deposit for the user, this call also transfers from them
        (uint256 shares, uint256 sharePrice) = _deposit(
            _contribution,
            _asUnderlying
        );

        // Perform a checkpoint.
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // If the LP total supply is zero, then the pool has never been
        // initialized or all of the active LP shares have been removed from
        // the pool and the withdrawal shares have all been paid out. We don't
        // need to check for this case because the share and bond reserves will
        // be zero, which will cause several function calls to fail.
        uint256 withdrawalSharesOutstanding = _totalSupply[
            AssetId._WITHDRAWAL_SHARE_ASSET_ID
        ] - _withdrawPool.readyToWithdraw;
        uint256 lpTotalSupply = _totalSupply[AssetId._LP_ASSET_ID] +
            withdrawalSharesOutstanding;

        // Calculate the number of LP shares to mint.
        uint256 endingPresentValue;
        {
            // Calculate the present value before updating the reserves.
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: _marketState.shareReserves,
                    bondReserves: _marketState.bondReserves,
                    sharePrice: sharePrice,
                    initialSharePrice: _initialSharePrice,
                    timeStretch: _timeStretch,
                    longsOutstanding: _marketState.longsOutstanding,
                    longAverageTimeRemaining: _calculateTimeRemaining(
                        uint256(_marketState.longAverageMaturityTime).divUp(
                            1e36
                        ) // scale to seconds
                    ),
                    shortsOutstanding: _marketState.shortsOutstanding,
                    shortAverageTimeRemaining: _calculateTimeRemaining(
                        uint256(_marketState.shortAverageMaturityTime).divUp(
                            1e36
                        ) // scale to seconds
                    ),
                    shortBaseVolume: _marketState.shortBaseVolume
                });
            uint256 startingPresentValue = HyperdriveMath.calculatePresentValue(
                params
            );

            // Add the liquidity to the pool's reserves and calculate the new
            // present value.
            _updateLiquidity(int256(shares));
            params.shareReserves = _marketState.shareReserves;
            params.bondReserves = _marketState.bondReserves;
            endingPresentValue = HyperdriveMath.calculatePresentValue(params);

            // The LP shares minted to the LP is derived by solving for the
            // change in LP shares that preserves the ratio of present value to
            // total LP shares. This ensures that LPs are fairly rewarded for
            // adding liquidity.This is given by:
            //
            // PV0 / l0 = PV1 / (l0 + dl) => dl = ((PV1 - PV0) * l0) / PV0
            lpShares = (endingPresentValue - startingPresentValue).mulDivDown(
                lpTotalSupply,
                startingPresentValue
            );
        }

        // By maintaining the ratio of present value to total LP shares, we may
        // end up increasing the idle that is available to withdraw by other
        // LPs. In this case, we pay out the proportional amount to the
        // withdrawal pool so that the withdrawal shares receive a corresponding
        // bump in their "idle" capital.
        uint256 currentValue = lpShares.mulDivDown(
            endingPresentValue,
            lpTotalSupply + lpShares
        );
        if (withdrawalSharesOutstanding > 0 && shares > currentValue) {
            uint256 withdrawalPoolProceeds = (shares - currentValue).mulDivDown(
                withdrawalSharesOutstanding,
                lpTotalSupply
            );
            _compensateWithdrawalPool(
                withdrawalPoolProceeds,
                endingPresentValue,
                lpTotalSupply + lpShares,
                withdrawalSharesOutstanding
            );
        }

        // Mint LP shares to the supplier.
        _mint(AssetId._LP_ASSET_ID, _destination, lpShares);

        // Emit an AddLiquidity event.
        emit AddLiquidity(_destination, lpShares, _contribution);
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
        uint256 totalActiveLpSupply = _totalSupply[AssetId._LP_ASSET_ID];
        uint256 withdrawalSharesOutstanding = _totalSupply[
            AssetId._WITHDRAWAL_SHARE_ASSET_ID
        ] - _withdrawPool.readyToWithdraw;
        uint256 totalLpSupply = totalActiveLpSupply +
            withdrawalSharesOutstanding;
        _burn(AssetId._LP_ASSET_ID, msg.sender, _shares);

        // Remove the liquidity from the pool.
        (
            uint256 shareProceeds,
            uint256 withdrawalShares
        ) = _applyRemoveLiquidity(
                _shares,
                sharePrice,
                totalLpSupply,
                totalActiveLpSupply,
                withdrawalSharesOutstanding
            );

        // Mint the withdrawal shares to the LP.
        _mint(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID,
            _destination,
            withdrawalShares
        );

        // Withdraw the shares from the yield source.
        uint256 baseProceeds = _withdraw(
            shareProceeds,
            _destination,
            _asUnderlying
        );

        // Enforce min user outputs
        if (_minOutput > baseProceeds) revert Errors.OutputLimit();

        // Emit a RemoveLiquidity event.
        uint256 shares = _shares;
        emit RemoveLiquidity(
            _destination,
            shares,
            baseProceeds,
            uint256(withdrawalShares)
        );

        return (baseProceeds, uint256(withdrawalShares));
    }

    /// @notice Redeems withdrawal shares by giving the LP a pro-rata amount of
    ///         the withdrawal pool's proceeds. This function redeems the
    ///         maximum amount of the specified withdrawal shares given the
    ///         amount of withdrawal shares ready to withdraw.
    /// @param _shares The withdrawal shares to redeem.
    /// @param _minOutputPerShare The minimum amount of base the LP expects to
    ///        receive for each withdrawal share that is burned.
    /// @param _destination The address which receive the withdraw proceeds
    /// @param _asUnderlying If true the user is paid in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return proceeds The amount of base the LP received.
    /// @return sharesRedeemed The amount of withdrawal shares that were redeemed.
    function redeemWithdrawalShares(
        uint256 _shares,
        uint256 _minOutputPerShare,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256, uint256) {
        // Perform a checkpoint.
        uint256 sharePrice = _pricePerShare();
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Clamp the shares to the total amount of shares ready for withdrawal
        // to avoid unnecessary reverts. We exit early if the user has no shares
        // available to redeem.
        if (_shares > _withdrawPool.readyToWithdraw) {
            _shares = _withdrawPool.readyToWithdraw;
        }
        if (_shares == 0) return (0, 0);

        // We burn the shares from the user
        _burn(AssetId._WITHDRAWAL_SHARE_ASSET_ID, msg.sender, _shares);

        // The LP gets the pro-rata amount of the collected proceeds.
        uint256 shareProceeds = _shares.mulDivDown(
            uint128(_withdrawPool.proceeds),
            uint128(_withdrawPool.readyToWithdraw)
        );

        // Apply the update to the withdrawal pool.
        _withdrawPool.readyToWithdraw -= uint128(_shares);
        _withdrawPool.proceeds -= uint128(shareProceeds);

        // Withdraw for the user
        uint256 proceeds = _withdraw(
            shareProceeds,
            _destination,
            _asUnderlying
        );

        // Enforce the minimum user output per share.
        if (_minOutputPerShare.mulDown(_shares) > proceeds)
            revert Errors.OutputLimit();

        // Emit a RedeemWithdrawalShares event.
        emit RedeemWithdrawalShares(_destination, _shares, proceeds);

        return (proceeds, _shares);
    }

    /// @dev Updates the pool's liquidity and holds the pool's APR constant.
    /// @param _shareReservesDelta The delta that should be applied to share reserves.
    function _updateLiquidity(int256 _shareReservesDelta) internal {
        // If the share reserves delta is equal to zero, there is no need to
        // update the reserves. If the share reserves are equal to zero, the
        // APR is undefined and the reserves cannot be updated. This only occurs
        // when all of the liquidity has been removed from the pool and the
        // only remaining positions are shorts. Otherwise, we update the pool
        // by increasing the share reserves and preserving the previous ratio of
        // share reserves to bond reserves.
        uint256 shareReserves = _marketState.shareReserves;
        if (_shareReservesDelta != 0 && shareReserves > 0) {
            int256 updatedShareReserves = int256(shareReserves) +
                _shareReservesDelta;
            _marketState.shareReserves = uint256(
                // NOTE: There is a 1 wei discrepancy in some of the
                // calculations which results in this clamping being required.
                updatedShareReserves >= 0 ? updatedShareReserves : int256(0)
            ).toUint128();
            _marketState.bondReserves = uint256(_marketState.bondReserves)
                .mulDivDown(_marketState.shareReserves, shareReserves)
                .toUint128();
        }
    }

    /// @dev Removes liquidity from the pool and calculates the amount of
    ///      withdrawal shares that should be minted.
    /// @param _shares The amount of shares to remove.
    /// @param _sharePrice The current price of a share.
    /// @param _totalLpSupply The total amount of LP shares.
    /// @param _totalActiveLpSupply The total amount of active LP shares.
    /// @param _withdrawalSharesOutstanding The total amount of withdrawal
    ///        shares outstanding.
    /// @return shareProceeds The share proceeds that will be paid to the LP.
    /// @return The amount of withdrawal shares that should be minted.
    function _applyRemoveLiquidity(
        uint256 _shares,
        uint256 _sharePrice,
        uint256 _totalLpSupply,
        uint256 _totalActiveLpSupply,
        uint256 _withdrawalSharesOutstanding
    ) internal returns (uint256 shareProceeds, uint256) {
        // Calculate the starting present value of the pool.
        HyperdriveMath.PresentValueParams memory params = HyperdriveMath
            .PresentValueParams({
                shareReserves: _marketState.shareReserves,
                bondReserves: _marketState.bondReserves,
                sharePrice: _sharePrice,
                initialSharePrice: _initialSharePrice,
                timeStretch: _timeStretch,
                longsOutstanding: _marketState.longsOutstanding,
                longAverageTimeRemaining: _calculateTimeRemaining(
                    uint256(_marketState.longAverageMaturityTime).divUp(1e36) // scale to seconds
                ),
                shortsOutstanding: _marketState.shortsOutstanding,
                shortAverageTimeRemaining: _calculateTimeRemaining(
                    uint256(_marketState.shortAverageMaturityTime).divUp(1e36) // scale to seconds
                ),
                shortBaseVolume: _marketState.shortBaseVolume
            });
        uint256 startingPresentValue = HyperdriveMath.calculatePresentValue(
            params
        );

        // The LP is given their share of the idle capital in the pool. This
        // is removed from the pool's reserves and paid out immediately. We use
        // the average opening share price of longs to avoid double counting
        // the variable rate interest accrued on long positions. The idle amount
        // is given by:
        //
        // idle = (z - (o_l / c_0)) * (dl / l_a)
        shareProceeds = _marketState.shareReserves;
        if (_marketState.longsOutstanding > 0) {
            shareProceeds -= uint256(_marketState.longsOutstanding).divDown(
                _marketState.longOpenSharePrice
            );
        }
        shareProceeds = shareProceeds.mulDivDown(_shares, _totalActiveLpSupply);
        _updateLiquidity(-int256(shareProceeds));
        params.shareReserves = _marketState.shareReserves;
        params.bondReserves = _marketState.bondReserves;
        uint256 endingPresentValue = HyperdriveMath.calculatePresentValue(
            params
        );

        // Calculate the amount of withdrawal shares that should be minted. We
        // solve for this value by solving the present value equation as
        // follows:
        //
        // PV0 / l0 = PV1 / (l0 - dl + dw) => dw = (PV1 / PV0) * l0 - (l0 - dl)
        int256 withdrawalShares = int256(
            _totalLpSupply.mulDivDown(endingPresentValue, startingPresentValue)
        );
        withdrawalShares -= int256(_totalLpSupply) - int256(_shares);
        if (withdrawalShares < 0) {
            // We backtrack by calculating the amount of the idle that should
            // be returned to the pool using the original present value ratio.
            uint256 overestimatedProceeds = startingPresentValue.mulDivDown(
                uint256(-withdrawalShares),
                _totalLpSupply
            );
            _updateLiquidity(int256(overestimatedProceeds));
            _applyWithdrawalProceeds(
                overestimatedProceeds,
                _withdrawalSharesOutstanding,
                _sharePrice
            );
            withdrawalShares = 0;
        }

        return (shareProceeds, uint256(withdrawalShares));
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
        uint256 presentValue = HyperdriveMath.calculatePresentValue(
            HyperdriveMath.PresentValueParams({
                shareReserves: _marketState.shareReserves,
                bondReserves: _marketState.bondReserves,
                sharePrice: _sharePrice,
                initialSharePrice: _initialSharePrice,
                timeStretch: _timeStretch,
                longsOutstanding: _marketState.longsOutstanding,
                longAverageTimeRemaining: _calculateTimeRemaining(
                    uint256(_marketState.longAverageMaturityTime).divUp(1e36) // scale to seconds
                ),
                shortsOutstanding: _marketState.shortsOutstanding,
                shortAverageTimeRemaining: _calculateTimeRemaining(
                    uint256(_marketState.shortAverageMaturityTime).divUp(1e36) // scale to seconds
                ),
                shortBaseVolume: _marketState.shortBaseVolume
            })
        );
        uint256 lpTotalSupply = _totalSupply[AssetId._LP_ASSET_ID] +
            _withdrawalSharesOutstanding;
        _compensateWithdrawalPool(
            _withdrawalProceeds,
            presentValue,
            lpTotalSupply,
            _withdrawalSharesOutstanding
        );
    }

    /// @dev Pays out a specified amount of withdrawal proceeds to the
    ///      withdrawal pool. This function is useful for circumstances in which
    ///      core calculations have already been performed to avoid reloading
    ///      state.
    /// @param _withdrawalProceeds The amount of withdrawal proceeds to pay out.
    /// @param _presentValue The present value of the pool.
    /// @param _lpTotalSupply The total supply of LP shares.
    /// @param _withdrawalSharesOutstanding The outstanding withdrawal shares.
    function _compensateWithdrawalPool(
        uint256 _withdrawalProceeds,
        uint256 _presentValue,
        uint256 _lpTotalSupply,
        uint256 _withdrawalSharesOutstanding
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
        uint256 maxSharesReleased = _presentValue > 0
            ? _lpTotalSupply.mulDivDown(_withdrawalProceeds, _presentValue)
            : _lpTotalSupply;
        if (maxSharesReleased == 0) return;

        // Calculate the amount of withdrawal shares that will be released and
        // the amount of capital that will be used to pay out the withdrawal
        // pool.
        uint256 sharesReleased = maxSharesReleased;
        uint256 withdrawalPoolProceeds = _withdrawalProceeds;
        if (maxSharesReleased > _withdrawalSharesOutstanding) {
            sharesReleased = _withdrawalSharesOutstanding;
            withdrawalPoolProceeds = _withdrawalProceeds.mulDivDown(
                sharesReleased,
                maxSharesReleased
            );
        }
        _withdrawPool.readyToWithdraw += uint128(sharesReleased);
        _withdrawPool.proceeds += uint128(withdrawalPoolProceeds);

        // Remove the withdrawal pool proceeds from the reserves.
        _updateLiquidity(-int256(withdrawalPoolProceeds));
    }
}
