// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { FixedPointMath, ONE } from "./FixedPointMath.sol";
import { HyperdriveMath } from "./HyperdriveMath.sol";
import { SafeCast } from "./SafeCast.sol";
import { YieldSpaceMath } from "./YieldSpaceMath.sol";

/// @author DELV
/// @title LPMath
/// @notice Math for the Hyperdrive LP system.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library LPMath {
    using FixedPointMath for *;

    /// @dev The maximum number of iterations for the share proceeds calculation.
    uint256 internal constant SHARE_PROCEEDS_MAX_ITERATIONS = 4;

    /// @dev The minimum tolerance for the share proceeds calculation to
    ///      short-circuit.
    uint256 internal constant SHARE_PROCEEDS_MIN_TOLERANCE = 1e9;

    /// @dev Calculates the new share reserves, share adjustment, and bond
    ///      reserves after liquidity is added or removed from the pool. This
    ///      update is made in such a way that the pool's spot price remains
    ///      constant.
    /// @param _shareReserves The current share reserves.
    /// @param _shareAdjustment The current share adjustment.
    /// @param _bondReserves The current bond reserves.
    /// @param _minimumShareReserves The minimum share reserves.
    /// @param _shareReservesDelta The change in share reserves.
    /// @return shareReserves The updated share reserves.
    /// @return shareAdjustment The updated share adjustment.
    /// @return bondReserves The updated bond reserves.
    function calculateUpdateLiquidity(
        uint256 _shareReserves,
        int256 _shareAdjustment,
        uint256 _bondReserves,
        uint256 _minimumShareReserves,
        int256 _shareReservesDelta
    )
        internal
        pure
        returns (
            uint256 shareReserves,
            int256 shareAdjustment,
            uint256 bondReserves
        )
    {
        // If the share reserves delta is zero, we can return early since no
        // action is needed.
        if (_shareReservesDelta == 0) {
            return (_shareReserves, _shareAdjustment, _bondReserves);
        }

        // Update the share reserves by applying the share reserves delta. We
        // ensure that our minimum share reserves invariant is still maintained.
        int256 shareReserves_ = int256(_shareReserves) + _shareReservesDelta;
        if (shareReserves_ < int256(_minimumShareReserves)) {
            revert IHyperdrive.InvalidShareReserves();
        }
        shareReserves = uint256(shareReserves_);

        // Update the share adjustment by holding the ratio of share reserves
        // to share adjustment proportional. In general, our pricing model cannot
        // support negative values for the z coordinate, so this is important as
        // it ensures that if z - zeta starts as a positive value, it ends as a
        // positive value. With this in mind, we update the share adjustment as:
        //
        // zeta_old / z_old = zeta_new / z_new
        //                  =>
        // zeta_new = zeta_old * (z_new / z_old)
        if (_shareAdjustment >= 0) {
            // NOTE: Rounding down to avoid introducing dust into the
            // computation.
            shareAdjustment = int256(
                shareReserves.mulDivDown(
                    uint256(_shareAdjustment),
                    _shareReserves
                )
            );
        } else {
            // NOTE: Rounding down to avoid introducing dust into the
            // computation.
            shareAdjustment = -int256(
                shareReserves.mulDivDown(
                    uint256(-_shareAdjustment),
                    _shareReserves
                )
            );
        }

        // NOTE: Rounding down to avoid introducing dust into the computation.
        //
        // The liquidity update should hold the spot price invariant. The spot
        // price of base in terms of bonds is given by:
        //
        // p = (mu * (z - zeta) / y) ** tau
        //
        // This formula implies that holding the ratio of share reserves to bond
        // reserves constant will hold the spot price constant. This allows us
        // to calculate the updated bond reserves as:
        //
        // (z_old - zeta_old) / y_old = (z_new - zeta_new) / y_new
        //                          =>
        // y_new = (z_new - zeta_new) * (y_old / (z_old - zeta_old))
        bondReserves = HyperdriveMath
            .calculateEffectiveShareReserves(shareReserves, shareAdjustment)
            .mulDivDown(
                _bondReserves,
                HyperdriveMath.calculateEffectiveShareReserves(
                    _shareReserves,
                    _shareAdjustment
                )
            );
    }

    struct PresentValueParams {
        uint256 shareReserves;
        int256 shareAdjustment;
        uint256 bondReserves;
        uint256 vaultSharePrice;
        uint256 initialVaultSharePrice;
        uint256 minimumShareReserves;
        uint256 timeStretch;
        uint256 longsOutstanding;
        uint256 longAverageTimeRemaining;
        uint256 shortsOutstanding;
        uint256 shortAverageTimeRemaining;
    }

    /// @dev Calculates the present value LPs capital in the pool and reverts
    ///      if the value is negative. This calculation underestimates the
    ///      present value to avoid paying out more than the pool can afford.
    /// @param _params The parameters for the present value calculation.
    /// @return The present value of the pool.
    function calculatePresentValue(
        PresentValueParams memory _params
    ) internal pure returns (uint256) {
        (uint256 presentValue, bool success) = calculatePresentValueSafe(
            _params
        );
        if (!success) {
            revert IHyperdrive.NegativePresentValue();
        }
        return presentValue;
    }

    /// @dev Calculates the present value LPs capital in the pool and returns
    ///      a flag indicating whether the calculation succeeded or failed.
    ///      For the most part, this calculation underestimates the present
    ///      value to avoid paying out more than the pool can afford; however,
    ///      it adheres faithfully to the rounding utilized when positions are
    ///      closed to accurately simulate the impact of closing the net curve
    ///      position.
    /// @param _params The parameters for the present value calculation.
    /// @return The present value of the pool.
    /// @return A flag indicating whether the calculation succeeded or failed.
    function calculatePresentValueSafe(
        PresentValueParams memory _params
    ) internal pure returns (uint256, bool) {
        // We calculate the LP present value by simulating the closing of all
        // of the outstanding long and short positions and applying this impact
        // on the share reserves. The present value is the share reserves after
        // the impact of the trades minus the minimum share reserves:
        //
        // PV = z + net_c + net_f - z_min
        int256 presentValue;
        {
            (int256 netCurveTrade, bool success) = calculateNetCurveTradeSafe(
                _params
            );
            if (!success) {
                return (0, false);
            }
            presentValue =
                int256(_params.shareReserves) +
                netCurveTrade +
                calculateNetFlatTrade(_params) -
                int256(_params.minimumShareReserves);
        }

        // If the present value is negative, return a status code indicating the
        // failure.
        if (presentValue < 0) {
            return (0, false);
        }

        return (uint256(presentValue), true);
    }

    /// @dev Calculates the result of closing the net curve position.
    /// @param _params The parameters for the present value calculation.
    /// @return The impact of closing the net curve position on the share
    ///         reserves.
    /// @return A flag indicating whether the calculation succeeded or failed.
    function calculateNetCurveTradeSafe(
        PresentValueParams memory _params
    ) internal pure returns (int256, bool) {
        // NOTE: To underestimate the impact of closing the net curve position,
        // we round up the long side of the net curve position (since this
        // results in a larger value removed from the share reserves) and round
        // down the short side of the net curve position (since this results in
        // a smaller value added to the share reserves).
        //
        // The net curve position is the net of the longs and shorts that are
        // currently tradeable on the curve. Given the amount of outstanding
        // longs `y_l` and shorts `y_s` as well as the average time remaining
        // of outstanding longs `t_l` and shorts `t_s`, we can
        // compute the net curve position as:
        //
        // netCurveTrade = y_l * t_l - y_s * t_s.
        int256 netCurvePosition = int256(
            _params.longsOutstanding.mulUp(_params.longAverageTimeRemaining)
        ) -
            int256(
                _params.shortsOutstanding.mulDown(
                    _params.shortAverageTimeRemaining
                )
            );
        uint256 effectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                _params.shareReserves,
                _params.shareAdjustment
            );

        // If the net curve position is positive, then the pool is net long.
        // Closing the net curve position results in the longs being paid out
        // from the share reserves, so we negate the result.
        if (netCurvePosition > 0) {
            uint256 netCurvePosition_ = uint256(netCurvePosition);

            // Calculate the maximum amount of bonds that can be sold on
            // YieldSpace. If this calculation fails, then we return a failure
            // flag.
            (uint256 maxCurveTrade, bool success) = YieldSpaceMath
                .calculateMaxSellBondsInSafe(
                    _params.shareReserves,
                    _params.shareAdjustment,
                    _params.bondReserves,
                    _params.minimumShareReserves,
                    ONE - _params.timeStretch,
                    _params.vaultSharePrice,
                    _params.initialVaultSharePrice
                );
            if (!success) {
                return (0, false);
            }

            // If the max curve trade is greater than the net curve position,
            // then we can close the entire net curve position.
            if (maxCurveTrade >= netCurvePosition_) {
                // NOTE: We round in the same direction as when closing longs
                // to accurately estimate the impact of closing the net curve
                // position.
                uint256 netCurveTrade = YieldSpaceMath
                    .calculateSharesOutGivenBondsInDown(
                        effectiveShareReserves,
                        _params.bondReserves,
                        netCurvePosition_,
                        ONE - _params.timeStretch,
                        _params.vaultSharePrice,
                        _params.initialVaultSharePrice
                    );
                return (-int256(netCurveTrade), true);
            }
            // Otherwise, we can only close part of the net curve position.
            // Since the spot price is approximately zero after closing the
            // entire net curve position, we mark any remaining bonds to zero.
            else {
                // If the share adjustment is greater than or equal to zero,
                // then the effective share reserves are less than or equal to
                // the share reserves. In this case, the maximum amount of
                // shares that can be removed from the share reserves is
                // `effectiveShareReserves - minimumShareReserves`.
                if (_params.shareAdjustment >= 0) {
                    return (
                        -int256(
                            effectiveShareReserves -
                                _params.minimumShareReserves
                        ),
                        true
                    );
                }
                // Otherwise, the effective share reserves are greater than the
                // share reserves. In this case, the maximum amount of shares
                // that can be removed from the share reserves is
                // `shareReserves - minimumShareReserves`.
                else {
                    return (
                        -int256(
                            _params.shareReserves - _params.minimumShareReserves
                        ),
                        true
                    );
                }
            }
        }
        // If the net curve position is negative, then the pool is net short.
        else if (netCurvePosition < 0) {
            uint256 netCurvePosition_ = uint256(-netCurvePosition);

            // Calculate the maximum amount of bonds that can be bought on
            // YieldSpace.
            uint256 maxCurveTrade = YieldSpaceMath.calculateMaxBuyBondsOut(
                effectiveShareReserves,
                _params.bondReserves,
                ONE - _params.timeStretch,
                _params.vaultSharePrice,
                _params.initialVaultSharePrice
            );

            // If the max curve trade is greater than the net curve position,
            // then we can close the entire net curve position.
            if (maxCurveTrade >= netCurvePosition_) {
                // NOTE: We round in the same direction as when closing shorts
                // to accurately estimate the impact of closing the net curve
                // position.
                uint256 netCurveTrade = YieldSpaceMath
                    .calculateSharesInGivenBondsOutUp(
                        effectiveShareReserves,
                        _params.bondReserves,
                        netCurvePosition_,
                        ONE - _params.timeStretch,
                        _params.vaultSharePrice,
                        _params.initialVaultSharePrice
                    );
                return (int256(netCurveTrade), true);
            }
            // Otherwise, we can only close part of the net curve position.
            // Since the spot price is equal to one after closing the entire net
            // curve position, we mark any remaining bonds to one.
            else {
                uint256 maxSharePayment = YieldSpaceMath
                    .calculateMaxBuySharesIn(
                        effectiveShareReserves,
                        _params.bondReserves,
                        ONE - _params.timeStretch,
                        _params.vaultSharePrice,
                        _params.initialVaultSharePrice
                    );
                return (
                    // NOTE: We round the difference down to underestimate the
                    // impact of closing the net curve position.
                    int256(
                        maxSharePayment +
                            (netCurvePosition_ - maxCurveTrade).divDown(
                                _params.vaultSharePrice
                            )
                    ),
                    true
                );
            }
        }

        return (0, true);
    }

    /// @dev Calculates the result of closing the net flat position.
    /// @param _params The parameters for the present value calculation.
    /// @return The impact of closing the net flat position on the share
    ///         reserves.
    function calculateNetFlatTrade(
        PresentValueParams memory _params
    ) internal pure returns (int256) {
        // NOTE: In order to underestimate the impact of closing all of the
        // flat trades, we round the impact of closing the shorts down and round
        // the impact of closing the longs up.
        //
        // The net curve position is the net of the component of longs and
        // shorts that have matured. Given the amount of outstanding longs `y_l`
        // and shorts `y_s` as well as the average time remaining of outstanding
        // longs `t_l` and shorts `t_s`, we can compute the net flat trade as:
        //
        // netFlatTrade = y_s * (1 - t_s) - y_l * (1 - t_l).
        return
            int256(
                _params.shortsOutstanding.mulDivDown(
                    ONE - _params.shortAverageTimeRemaining,
                    _params.vaultSharePrice
                )
            ) -
            int256(
                _params.longsOutstanding.mulDivUp(
                    ONE - _params.longAverageTimeRemaining,
                    _params.vaultSharePrice
                )
            );
    }

    struct DistributeExcessIdleParams {
        PresentValueParams presentValueParams;
        uint256 startingPresentValue;
        uint256 activeLpTotalSupply;
        uint256 withdrawalSharesTotalSupply;
        uint256 idle;
        int256 netCurveTrade;
        uint256 originalShareReserves;
        int256 originalShareAdjustment;
        uint256 originalBondReserves;
    }

    /// @dev Calculates the amount of withdrawal shares that can be redeemed and
    ///      the share proceeds the withdrawal pool should receive given the
    ///      pool's current idle liquidity. We use the following algorith to
    ///      ensure that the withdrawal pool receives the correct amount of
    ///      shares to (1) preserve the LP share price and (2) pay out as much
    ///      of the idle liquidity as possible to the withdrawal pool:
    ///
    ///      1. If `y_s * t_s <= y_l * t_l` or
    ///         `y_max_out(I) >= y_s * t_s - y_l * t_l`, set `dz_max = I` and
    ///         proceed to step (3). Otherwise, proceed to step (2).
    ///      2. Solve `y_max_out(dz_max) = y_s * t_s - y_l * t_l` for `dz_max`
    ///         using Newton's method.
    ///      3. Set `dw = (1 - PV(dz_max) / PV(0)) * l`. If `dw <= w`, then
    ///         proceed to step (5). Otherwise, set `dw = w` and continue to
    ///         step (4).
    ///      4. Solve `PV(0) / l = PV(dz) / (l - dw)` for `dz` using Newton's
    ///         method if `y_l * t_l != y_s * t_s` or directly otherwise.
    ///      5. Return `dw` and `dz`.
    /// @param _params The parameters for the distribute excess idle.
    /// @return The amount of withdrawal shares that can be redeemed.
    /// @return The share proceeds the withdrawal pool should receive.
    function calculateDistributeExcessIdle(
        DistributeExcessIdleParams memory _params
    ) internal pure returns (uint256, uint256) {
        // Steps 1 and 2: Calculate the maximum amount the share reserves can be
        // debited.
        uint256 originalEffectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                _params.originalShareReserves,
                _params.originalShareAdjustment
            );
        uint256 maxShareReservesDelta = calculateMaxShareReservesDelta(
            _params,
            originalEffectiveShareReserves
        );

        // Step 3: Calculate the amount of withdrawal shares that can be
        // redeemed given the maximum share reserves delta.  Otherwise, we
        // proceed to calculating the amount of shares that should be paid out
        // to redeem all of the withdrawal shares.
        uint256 withdrawalSharesRedeemed = calculateDistributeExcessIdleWithdrawalSharesRedeemed(
                _params,
                maxShareReservesDelta
            );

        // Step 3: If none of the withdrawal shares could be redeemed, then
        // we're done and we pay out nothing.
        if (withdrawalSharesRedeemed == 0) {
            return (0, 0);
        }
        // Step 3: Otherwise if this amount is less than or equal to the amount
        // of withdrawal shares outstanding, then we're done and we pay out the
        // full maximum share reserves delta.
        else if (
            withdrawalSharesRedeemed <= _params.withdrawalSharesTotalSupply
        ) {
            return (withdrawalSharesRedeemed, maxShareReservesDelta);
        }
        // Step 3: Otherwise, all of the withdrawal shares are redeemed, and we
        // need to calculate the amount of shares the withdrawal pool should
        // receive.
        else {
            withdrawalSharesRedeemed = _params.withdrawalSharesTotalSupply;
        }

        // Step 4: Solve for the share proceeds that hold the LP share price
        // invariant after all of the withdrawal shares are redeemed. If the
        // calculation returns a share proceeds of zero, we can't pay out
        // anything.
        uint256 shareProceeds = calculateDistributeExcessIdleShareProceeds(
            _params,
            originalEffectiveShareReserves,
            maxShareReservesDelta
        );
        if (shareProceeds == 0) {
            return (0, 0);
        }

        // Step 4: If the share proceeds are greater than or equal to the
        // maximum share reserves delta that was previously calculated, then
        // we can't distribute excess idle since we ruled out the possibility
        // of paying out the full maximum share reserves delta in step 3.
        if (shareProceeds >= maxShareReservesDelta) {
            return (0, 0);
        }

        // Step 5: Return the amount of withdrawal shares redeemed and the
        // share proceeds.
        return (withdrawalSharesRedeemed, shareProceeds);
    }

    /// @dev Calculates the amount of withdrawal shares that can be redeemed
    ///      given an amount of shares to remove from the share reserves.
    ///      Assuming that dz is the amount of shares to remove from the
    ///      reserves and dl is the amount of LP shares to be burned, we can
    ///      derive the calculation as follows:
    ///
    ///      PV(0) / l = PV(dx) / (l - dl)
    ///                =>
    ///      dl = l - l * (PV(dx) / PV(0))
    ///
    ///      We round this calculation up to err on the side of slightly too
    ///      many withdrawal shares being redeemed.
    /// @param _params The parameters for the present value calculation.
    /// @param _shareReservesDelta The amount of shares to remove from the
    ///        share reserves.
    /// @return The amount of withdrawal shares that can be redeemed.
    function calculateDistributeExcessIdleWithdrawalSharesRedeemed(
        DistributeExcessIdleParams memory _params,
        uint256 _shareReservesDelta
    ) internal pure returns (uint256) {
        // Calculate the present value after debiting the share reserves delta.
        (
            _params.presentValueParams.shareReserves,
            _params.presentValueParams.shareAdjustment,
            _params.presentValueParams.bondReserves
        ) = calculateUpdateLiquidity(
            _params.originalShareReserves,
            _params.originalShareAdjustment,
            _params.originalBondReserves,
            _params.presentValueParams.minimumShareReserves,
            -int256(_shareReservesDelta)
        );
        (uint256 endingPresentValue, bool success) = calculatePresentValueSafe(
            _params.presentValueParams
        );

        // If the present value calculation failed or if the ending present
        // value is greater than the starting present value, we short-circuit to
        // avoid distributing excess idle. This edge-case can occur when the
        // share reserves is very close to the minimum share reserves with a
        // large value of k.
        if (!success || endingPresentValue >= _params.startingPresentValue) {
            return 0;
        }

        // NOTE: This subtraction is safe since the ending present value is less
        // than the starting present value and the rhs is rounded down.
        //
        // Calculate the amount of withdrawal shares that can be redeemed.
        uint256 lpTotalSupply = _params.activeLpTotalSupply +
            _params.withdrawalSharesTotalSupply;
        return
            lpTotalSupply -
            lpTotalSupply.mulDivDown(
                endingPresentValue,
                _params.startingPresentValue
            );
    }

    /// @dev Calculates the share proceeds to distribute to the withdrawal pool
    ///      assuming that all of the outstanding withdrawal shares will be
    ///      redeemed. The share proceeds are calculated such that the LP share
    ///      price is conserved. When we need to round, we round down to err on
    ///      the side of slightly too few shares being paid out.
    /// @param _params The parameters for the distribute excess idle calculation.
    /// @param _originalEffectiveShareReserves The original effective share
    ///        reserves.
    /// @param _maxShareReservesDelta The maximum change in the share reserves
    ///        that can result from distributing excess idle. This provides an
    ///        upper bound on the share proceeds returned from this calculation.
    /// @return The share proceeds to distribute to the withdrawal pool.
    function calculateDistributeExcessIdleShareProceeds(
        DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves,
        uint256 _maxShareReservesDelta
    ) internal pure returns (uint256) {
        // Calculate the LP total supply.
        uint256 lpTotalSupply = _params.activeLpTotalSupply +
            _params.withdrawalSharesTotalSupply;

        // NOTE: Round the initial guess down to avoid overshooting.
        //
        // We make an initial guess for Newton's method by assuming that the
        // ratio of the share reserves delta to the withdrawal shares
        // outstanding is equal to the LP share price. In reality, the
        // withdrawal pool should receive more than this, but it's a good
        // starting point. The calculation is:
        //
        // x_0 = w * (PV(0) / l)
        uint256 shareProceeds = _params.withdrawalSharesTotalSupply.mulDivDown(
            _params.startingPresentValue,
            lpTotalSupply
        );

        // If the pool is net neutral, the initial guess is equal to the final
        // result.
        if (_params.netCurveTrade == 0) {
            return shareProceeds;
        }

        // If the net curve trade is positive, the pool is net long.
        if (_params.netCurveTrade > 0) {
            for (uint256 i = 0; i < SHARE_PROCEEDS_MAX_ITERATIONS; ) {
                // Clamp the share proceeds to the max share reserves delta
                // since values above this threshold are always invalid.
                shareProceeds = shareProceeds.min(_maxShareReservesDelta);

                // Simulate applying the share proceeds to the reserves and
                // recalculate the present value.
                (
                    _params.presentValueParams.shareReserves,
                    _params.presentValueParams.shareAdjustment,
                    _params.presentValueParams.bondReserves
                ) = calculateUpdateLiquidity(
                    _params.originalShareReserves,
                    _params.originalShareAdjustment,
                    _params.originalBondReserves,
                    _params.presentValueParams.minimumShareReserves,
                    -int256(shareProceeds)
                );
                uint256 presentValue = calculatePresentValue(
                    _params.presentValueParams
                );

                // Short-circuit if we are within the minimum tolerance.
                if (
                    shouldShortCircuitDistributeExcessIdleShareProceeds(
                        _params,
                        presentValue,
                        lpTotalSupply
                    )
                ) {
                    break;
                }

                // If the net curve trade is less than or equal to the maximum
                // amount of bonds that can be sold with this share proceeds, we
                // can calculate the derivative using the derivative of
                // `calculateSharesOutGivenBondsIn`.
                DistributeExcessIdleParams memory params = _params; // avoid stack-too-deep
                (uint256 maxBondAmount, bool success) = YieldSpaceMath
                    .calculateMaxSellBondsInSafe(
                        params.presentValueParams.shareReserves,
                        params.presentValueParams.shareAdjustment,
                        params.presentValueParams.bondReserves,
                        params.presentValueParams.minimumShareReserves,
                        ONE - _params.presentValueParams.timeStretch,
                        params.presentValueParams.vaultSharePrice,
                        params.presentValueParams.initialVaultSharePrice
                    );
                if (!success) {
                    // NOTE: If the max bond amount couldn't be calculated, we
                    // can't continue the calculation. Return 0 to indicate that
                    // the share proceeds couldn't be calculated.
                    return 0;
                }
                uint256 derivative;
                if (uint256(_params.netCurveTrade) <= maxBondAmount) {
                    (
                        derivative,
                        success
                    ) = calculateSharesOutGivenBondsInDerivativeSafe(
                        params,
                        _originalEffectiveShareReserves,
                        uint256(_params.netCurveTrade)
                    );
                    if (!success || derivative >= ONE) {
                        // NOTE: Return 0 to indicate that the share proceeds
                        // couldn't be calculated.
                        return 0;
                    }
                    derivative = ONE - derivative;
                }
                // Otherwise, the objective becomes linear, and we can solve for
                // the next step in Newton's method directly.
                else {
                    // Solve the objective function directly assuming that it is
                    // linear with respect to the share proceeds.
                    (
                        shareProceeds,
                        success
                    ) = calculateDistributeExcessIdleShareProceedsNetLongEdgeCaseSafe(
                        params
                    );
                    if (!success) {
                        // NOTE: Return 0 to indicate that the share proceeds
                        // couldn't be calculated.
                        return 0;
                    }

                    // Simulate applying the share proceeds to the reserves and
                    // recalculate the max bond amount.
                    (
                        _params.presentValueParams.shareReserves,
                        _params.presentValueParams.shareAdjustment,
                        _params.presentValueParams.bondReserves
                    ) = calculateUpdateLiquidity(
                        _params.originalShareReserves,
                        _params.originalShareAdjustment,
                        _params.originalBondReserves,
                        _params.presentValueParams.minimumShareReserves,
                        -int256(shareProceeds)
                    );
                    DistributeExcessIdleParams memory params = _params;
                    (maxBondAmount, success) = YieldSpaceMath
                        .calculateMaxSellBondsInSafe(
                            params.presentValueParams.shareReserves,
                            params.presentValueParams.shareAdjustment,
                            params.presentValueParams.bondReserves,
                            params.presentValueParams.minimumShareReserves,
                            ONE - _params.presentValueParams.timeStretch,
                            params.presentValueParams.vaultSharePrice,
                            params.presentValueParams.initialVaultSharePrice
                        );
                    if (!success) {
                        // NOTE: Return 0 to indicate that the share proceeds
                        // couldn't be calculated.
                        return 0;
                    }

                    // If the max bond amount is greater than or equal to the
                    // net curve trade, then Newton's method has terminated since
                    // proceeding to the next step would result in reaching the
                    // same point.
                    if (maxBondAmount >= uint256(_params.netCurveTrade)) {
                        return shareProceeds;
                    }
                    // Otherwise, we continue to the next iteration of Newton's
                    // method.
                    else {
                        continue;
                    }
                }

                // NOTE: Round the delta down to avoid overshooting.
                //
                // We calculate the updated share proceeds `x_n+1` by proceeding
                // with Newton's method. This is given by:
                //
                // x_n+1 = x_n - F(x_n) / F'(x_n)
                //
                // where our objective function `F(x)` is:
                //
                // F(x) = PV(x) * l - PV(0) * (l - w)
                int256 delta = int256(presentValue.mulDown(lpTotalSupply)) -
                    int256(
                        params.startingPresentValue.mulUp(
                            params.activeLpTotalSupply
                        )
                    );
                if (delta > 0) {
                    // NOTE: Round the quotient down to avoid overshooting.
                    shareProceeds =
                        shareProceeds +
                        uint256(delta).divDown(derivative.mulUp(lpTotalSupply));
                } else if (delta < 0) {
                    // NOTE: Round the quotient down to avoid overshooting.
                    uint256 delta_ = uint256(-delta).divDown(
                        derivative.mulUp(lpTotalSupply)
                    );
                    if (delta_ < shareProceeds) {
                        shareProceeds = shareProceeds - delta_;
                    } else {
                        // NOTE: Returning 0 to indicate that the share proceeds
                        // couldn't be calculated.
                        return 0;
                    }
                } else {
                    break;
                }

                // Increment the loop counter.
                unchecked {
                    ++i;
                }
            }
        }
        // Otherwise, the pool is net short.
        else {
            for (uint256 i = 0; i < SHARE_PROCEEDS_MAX_ITERATIONS; ) {
                // Clamp the share proceeds to the max share reserves delta
                // since values above this threshold are always invalid.
                shareProceeds = shareProceeds.min(_maxShareReservesDelta);

                // Simulate applying the share proceeds to the reserves and
                // recalculate the present value.
                (
                    _params.presentValueParams.shareReserves,
                    _params.presentValueParams.shareAdjustment,
                    _params.presentValueParams.bondReserves
                ) = calculateUpdateLiquidity(
                    _params.originalShareReserves,
                    _params.originalShareAdjustment,
                    _params.originalBondReserves,
                    _params.presentValueParams.minimumShareReserves,
                    -int256(shareProceeds)
                );
                uint256 presentValue = calculatePresentValue(
                    _params.presentValueParams
                );

                // Short-circuit if we are within the minimum tolerance.
                if (
                    shouldShortCircuitDistributeExcessIdleShareProceeds(
                        _params,
                        presentValue,
                        lpTotalSupply
                    )
                ) {
                    break;
                }

                // Since the share proceeds are clamped to the max share
                // reserves delta, we are always operating with the regime where
                // the net curve trade is less than the maximum bond amount.
                // With this in mind, we can calculate the derivative using the
                // derivative of `calculateSharesOutGivenBondsIn`.
                (
                    uint256 derivative,
                    bool success
                ) = calculateSharesInGivenBondsOutDerivativeSafe(
                        _params,
                        _originalEffectiveShareReserves,
                        uint256(-_params.netCurveTrade)
                    );
                if (!success || derivative >= ONE) {
                    // NOTE: Return 0 to indicate that the share proceeds
                    // couldn't be calculated.
                    return 0;
                }
                derivative = ONE - derivative;

                // NOTE: Round the delta down to avoid overshooting.
                //
                // We calculate the updated share proceeds `x_n+1` by proceeding
                // with Newton's method. This is given by:
                //
                // x_n+1 = x_n - F(x_n) / F'(x_n)
                //
                // where our objective function `F(x)` is:
                //
                // F(x) = PV(x) * l - PV(0) * (l - w)
                int256 delta = int256(presentValue.mulDown(lpTotalSupply)) -
                    int256(
                        _params.startingPresentValue.mulUp(
                            _params.activeLpTotalSupply
                        )
                    );
                if (delta > 0) {
                    // NOTE: Round the quotient down to avoid overshooting.
                    shareProceeds =
                        shareProceeds +
                        uint256(delta).divDown(derivative).divDown(
                            lpTotalSupply
                        );
                } else if (delta < 0) {
                    // NOTE: Round the quotient down to avoid overshooting.
                    uint256 delta_ = uint256(-delta)
                        .divDown(derivative)
                        .divDown(lpTotalSupply);
                    if (delta_ < shareProceeds) {
                        shareProceeds = shareProceeds - delta_;
                    } else {
                        // NOTE: Returning 0 to indicate that the share proceeds
                        // couldn't be calculated.
                        return 0;
                    }
                } else {
                    break;
                }

                // Increment the loop counter.
                unchecked {
                    ++i;
                }
            }
        }

        return shareProceeds;
    }

    /// @dev One of the edge cases that occurs when using Newton's method for
    ///      the share proceeds while distributing excess idle is when the net
    ///      curve trade is larger than the max bond amount. In this case, the
    ///      the present value simplifies to the following:
    ///
    ///      PV(dz) = (z - dz) + net_c(dz) + net_f - z_min
    ///             = (z - dz) - y_max_out(dz) + net_f - z_min
    ///
    ///      There are two cases to evaluate:
    ///
    ///      (1) zeta > 0:
    ///
    ///          y_max_out(dz) = (z - dz) - zeta * ((z - dz) / z) - z_min
    ///
    ///          =>
    ///
    ///          PV(dz) = zeta * ((z - dz) / z) + net_f
    ///
    ///      (2) zeta <= 0:
    ///
    ///          y_max_out(dz) = (z - dz) - z_min
    ///
    ///          =>
    ///
    ///          PV(dz) = net_f
    ///
    ///      Since the present value is constant with respect to the share
    ///      proceeds in case 2, Newton's method has achieved a stationary point
    ///      and can't proceed. On the other hand, the present value is linear
    ///      with respect to the share proceeds, and we can solve for the next
    ///      step of Newton's method directly as follows:
    ///
    ///      PV(0) / l = PV(dz) / (l - w)
    ///
    ///      =>
    ///
    ///      dz = z - ((PV(0) / l) * (l - w) - net_f) / (zeta / z)
    ///
    ///      We round the share proceeds down to err on the side of the
    ///      withdrawal pool receiving slightly less shares.
    /// @param _params The parameters for the calculation.
    /// @return The share proceeds.
    /// @return A flag indicating whether the calculation was successful.
    function calculateDistributeExcessIdleShareProceedsNetLongEdgeCaseSafe(
        DistributeExcessIdleParams memory _params
    ) internal pure returns (uint256, bool) {
        // If the original share adjustment is zero or negative, we cannot
        // calculate the share proceeds. This should never happen, but for
        // safety we return a failure flag and break the loop at this point.
        if (_params.originalShareAdjustment <= 0) {
            return (0, false);
        }

        // Calculate the net flat trade.
        int256 netFlatTrade = calculateNetFlatTrade(_params.presentValueParams);

        // NOTE: Round up since this is the rhs of the final subtraction.
        //
        // rhs = (PV(0) / l) * (l - w) - net_f
        uint256 rhs;
        if (netFlatTrade >= 0) {
            rhs =
                _params.startingPresentValue.mulDivUp(
                    _params.activeLpTotalSupply,
                    _params.activeLpTotalSupply +
                        _params.withdrawalSharesTotalSupply
                ) -
                uint256(netFlatTrade);
        } else {
            rhs =
                _params.startingPresentValue.mulDivUp(
                    _params.activeLpTotalSupply,
                    _params.activeLpTotalSupply +
                        _params.withdrawalSharesTotalSupply
                ) +
                uint256(-netFlatTrade);
        }

        // NOTE: Round up since this is the rhs of the final subtraction.
        //
        // rhs = ((PV(0) / l) * (l - w) - net_f) / (zeta / z)
        rhs = _params.originalShareReserves.mulDivUp(
            rhs,
            uint256(_params.originalShareAdjustment)
        );

        // share proceeds = z - rhs
        return (_params.originalShareReserves - rhs, true);
    }

    /// @dev Checks to see if we should short-circuit the iterative calculation
    ///     of the share proceeds when distributing excess idle liquidity. This
    ///     verifies that the ending LP share price is greater than or equal to
    ///     the starting LP share price and less than or equal to the starting
    ///     LP share price plus the minimum tolerance.
    /// @param _params The parameters for the calculation.
    /// @param _lpTotalSupply The total supply of LP shares.
    /// @param _presentValue The present value of the pool at this iteration of
    ///        the calculation.
    /// @return A flag indicating whether or not we should short-circuit the
    ///         calculation.
    function shouldShortCircuitDistributeExcessIdleShareProceeds(
        DistributeExcessIdleParams memory _params,
        uint256 _lpTotalSupply,
        uint256 _presentValue
    ) internal pure returns (bool) {
        uint256 lpSharePriceBefore = _params.startingPresentValue.divDown(
            _lpTotalSupply
        );
        uint256 lpSharePriceAfter = _presentValue.divDown(
            _params.activeLpTotalSupply
        );
        return
            lpSharePriceAfter >= lpSharePriceBefore &&
            lpSharePriceAfter <=
            // NOTE: Round down to make the check stricter.
            lpSharePriceBefore.mulDown(ONE + SHARE_PROCEEDS_MIN_TOLERANCE);
    }

    /// @dev Calculates the upper bound on the share proceeds of distributing
    ///      excess idle. When the pool is net long or net neutral, the upper
    ///      bound is the amount of idle liquidity. When the pool is net short,
    ///      the upper bound is the share reserves delta that results in the
    ///      maximum amount of bonds that can be purchased being equal to the
    ///      net short position.
    /// @param _params The parameters for the distribute excess idle calculation.
    /// @param _originalEffectiveShareReserves The original effective share
    ///        reserves.
    /// @return maxShareReservesDelta The upper bound on the share proceeds.
    function calculateMaxShareReservesDelta(
        DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves
    ) internal pure returns (uint256 maxShareReservesDelta) {
        // If the net curve position is zero or net long, then the maximum
        // share reserves delta is equal to the pool's idle.
        if (_params.netCurveTrade >= 0) {
            return _params.idle;
        }
        uint256 netCurveTrade = uint256(-_params.netCurveTrade);

        // We can solve for the maximum share reserves delta in one shot using
        // the fact that the maximum amount of bonds that can be purchased is
        // linear with respect to the scaling factor applied to the reserves.
        // In other words, if s > 0 is a factor scaling the reserves, we have
        // the following relationship:
        //
        // y_out^max(s * z, s * y, s * zeta) = s * y_out^max(z, y, zeta)
        //
        // We solve for the maximum share reserves delta by finding the scaling
        // factor that results in the maximum amount of bonds that can be
        // purchased being equal to the net curve trade. We can derive this
        // maximum using the linearity property mentioned above as follows:
        //
        // y_out^max(s * z, s * y, s * zeta) - netCurveTrade = 0
        //                        =>
        // s * y_out^max(z, y, zeta) - netCurveTrade = 0
        //                        =>
        // s = netCurveTrade / y_out^max(z, y, zeta)
        uint256 maxScalingFactor = netCurveTrade.divUp(
            YieldSpaceMath.calculateMaxBuyBondsOut(
                _originalEffectiveShareReserves,
                _params.originalBondReserves,
                ONE - _params.presentValueParams.timeStretch,
                _params.presentValueParams.vaultSharePrice,
                _params.presentValueParams.initialVaultSharePrice
            )
        );

        // Using the maximum scaling factor, we can calculate the maximum share
        // reserves delta as:
        //
        // maxShareReservesDelta = z * (1 - s)
        if (maxScalingFactor <= ONE) {
            maxShareReservesDelta = _params.originalShareReserves.mulDown(
                ONE - maxScalingFactor
            );
        } else {
            return 0;
        }

        // If the maximum share reserves delta is greater than the idle, then
        // the maximum share reserves delta is equal to the idle.
        if (maxShareReservesDelta > _params.idle) {
            return _params.idle;
        }
        return maxShareReservesDelta;
    }

    /// @dev Calculates the derivative of `calculateSharesOutGivenBondsIn`. This
    ///      derivative is given by:
    ///
    ///      derivative = - (1 - zeta / z) * (
    ///          1 - (1 / c) * (
    ///              c * (mu * z_e(x)) ** -t_s +
    ///              (y / z_e) * y(x) ** -t_s  -
    ///              (y / z_e) * (y(x) + dy) ** -t_s
    ///          ) * (
    ///              (mu / c) * (k(x) - (y(x) + dy) ** (1 - t_s))
    ///          ) ** (t_s / (1 - t_s))
    ///      )
    ///
    ///      We round down to avoid overshooting the optimal solution in Newton's
    ///      method (the derivative we use is 1 minus this derivative so this
    ///      rounds the derivative up).
    /// @param _params The parameters for the calculation.
    /// @param _originalEffectiveShareReserves The original effective share
    ///        reserves.
    /// @param _bondAmount The amount of bonds to sell.
    /// @return The derivative.
    /// @return A flag indicating whether the derivative could be computed.
    function calculateSharesOutGivenBondsInDerivativeSafe(
        DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves,
        uint256 _bondAmount
    ) internal pure returns (uint256, bool) {
        // NOTE: Round up since this is on the rhs of the final subtraction.
        //
        // derivative = c * (mu * z_e(x)) ** -t_s +
        //              (y / z_e) * (y(x)) ** -t_s -
        //              (y / z_e) * (y(x) + dy) ** -t_s
        uint256 effectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                _params.presentValueParams.shareReserves,
                _params.presentValueParams.shareAdjustment
            );
        uint256 derivative = _params.presentValueParams.vaultSharePrice.divUp(
            _params
                .presentValueParams
                .initialVaultSharePrice
                .mulDown(effectiveShareReserves)
                .pow(_params.presentValueParams.timeStretch)
        ) +
            _params.originalBondReserves.divUp(
                _originalEffectiveShareReserves.mulDown(
                    _params.presentValueParams.bondReserves.pow(
                        _params.presentValueParams.timeStretch
                    )
                )
            ) -
            // NOTE: Round down to round the subtraction up.
            _params.originalBondReserves.divDown(
                _originalEffectiveShareReserves.mulUp(
                    (_params.presentValueParams.bondReserves + _bondAmount).pow(
                        _params.presentValueParams.timeStretch
                    )
                )
            );

        // NOTE: Round up since this is on the rhs of the final subtraction.
        //
        // inner = (
        //             (mu / c) * (k(x) - (y(x) + dy) ** (1 - t_s))
        //         ) ** (t_s / (1 - t_s))
        uint256 k = YieldSpaceMath.kUp(
            effectiveShareReserves,
            _params.presentValueParams.bondReserves,
            ONE - _params.presentValueParams.timeStretch,
            _params.presentValueParams.vaultSharePrice,
            _params.presentValueParams.initialVaultSharePrice
        );
        uint256 inner = (_params.presentValueParams.bondReserves + _bondAmount)
            .pow(ONE - _params.presentValueParams.timeStretch);
        if (k < inner) {
            // NOTE: In this case, we shouldn't proceed with distributing excess
            // idle since the derivative couldn't be computed.
            return (0, false);
        }
        inner = _params.presentValueParams.initialVaultSharePrice.mulDivUp(
            k - inner,
            _params.presentValueParams.vaultSharePrice
        );
        if (inner >= ONE) {
            // NOTE: Round the exponent up since this rounds the result up.
            inner = inner.pow(
                _params.presentValueParams.timeStretch.divUp(
                    ONE - _params.presentValueParams.timeStretch
                )
            );
        } else {
            // NOTE: Round the exponent down since this rounds the result up.
            inner = inner.pow(
                _params.presentValueParams.timeStretch.divDown(
                    ONE - _params.presentValueParams.timeStretch
                )
            );
        }

        // NOTE: Round up since this is on the rhs of the final subtraction.
        derivative = derivative.mulDivUp(
            inner,
            _params.presentValueParams.vaultSharePrice
        );

        // derivative = 1 - derivative
        if (ONE >= derivative) {
            derivative = ONE - derivative;
        } else {
            // NOTE: Small rounding errors can result in the derivative being
            // slightly (on the order of a few wei) greater than 1. In this case,
            // we return 0 since we should proceed with Newton's method.
            return (0, true);
        }

        // NOTE: Round down to round the final result down.
        //
        // derivative = derivative * (1 - (zeta / z))
        if (_params.originalShareAdjustment >= 0) {
            derivative = derivative.mulDown(
                ONE -
                    uint256(_params.originalShareAdjustment).divUp(
                        _params.originalShareReserves
                    )
            );
        } else {
            derivative = derivative.mulDown(
                ONE +
                    uint256(-_params.originalShareAdjustment).divDown(
                        _params.originalShareReserves
                    )
            );
        }

        return (derivative, true);
    }

    /// @dev Calculates the derivative of `calculateSharesInGivenBondsOut`. This
    ///      derivative is given by:
    ///
    ///      derivative = - (1 - zeta / z) * (
    ///          (1 / c) * (
    ///              c * (mu * z_e(x)) ** -t_s +
    ///              (y / z_e) * y(x) ** -t_s  -
    ///              (y / z_e) * (y(x) - dy) ** -t_s
    ///          ) * (
    ///              (mu / c) * (k(x) - (y(x) - dy) ** (1 - t_s))
    ///          ) ** (t_s / (1 - t_s)) - 1
    ///      )
    ///
    ///      We round down to avoid overshooting the optimal solution in
    ///      Newton's method (the derivative we use is 1 minus this derivative
    ///      so this rounds the derivative up).
    /// @param _params The parameters for the calculation.
    /// @param _originalEffectiveShareReserves The original effective share
    ///        reserves.
    /// @param _bondAmount The amount of bonds to sell.
    /// @return The derivative.
    /// @return A flag indicating whether the derivative could be computed.
    function calculateSharesInGivenBondsOutDerivativeSafe(
        DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves,
        uint256 _bondAmount
    ) internal pure returns (uint256, bool) {
        // NOTE: Round up since this is on the rhs of the final subtraction.
        //
        // derivative = c * (mu * z_e(x)) ** -t_s +
        //              (y / z_e) * (y(x)) ** -t_s -
        //              (y / z_e) * (y(x) - dy) ** -t_s
        uint256 effectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                _params.presentValueParams.shareReserves,
                _params.presentValueParams.shareAdjustment
            );
        uint256 derivative = _params.presentValueParams.vaultSharePrice.divUp(
            _params
                .presentValueParams
                .initialVaultSharePrice
                .mulDown(effectiveShareReserves)
                .pow(_params.presentValueParams.timeStretch)
        ) +
            _params.originalBondReserves.divUp(
                _originalEffectiveShareReserves.mulDown(
                    _params.presentValueParams.bondReserves.pow(
                        _params.presentValueParams.timeStretch
                    )
                )
            ) -
            // NOTE: Round down this rounds the subtraction up.
            _params.originalBondReserves.divDown(
                _originalEffectiveShareReserves.mulUp(
                    (_params.presentValueParams.bondReserves - _bondAmount).pow(
                        _params.presentValueParams.timeStretch
                    )
                )
            );

        // NOTE: Round up since this is on the rhs of the final subtraction.
        //
        // inner = (
        //             (mu / c) * (k(x) - (y(x) - dy) ** (1 - t_s))
        //         ) ** (t_s / (1 - t_s))
        uint256 k = YieldSpaceMath.kUp(
            effectiveShareReserves,
            _params.presentValueParams.bondReserves,
            ONE - _params.presentValueParams.timeStretch,
            _params.presentValueParams.vaultSharePrice,
            _params.presentValueParams.initialVaultSharePrice
        );
        uint256 inner = (_params.presentValueParams.bondReserves - _bondAmount)
            .pow(ONE - _params.presentValueParams.timeStretch);
        if (k < inner) {
            // NOTE: In this case, we shouldn't proceed with distributing excess
            // idle since the derivative couldn't be computed.
            return (0, false);
        }
        inner = _params.presentValueParams.initialVaultSharePrice.mulDivUp(
            k - inner,
            _params.presentValueParams.vaultSharePrice
        );
        if (inner >= ONE) {
            // NOTE: Round the exponent up since this rounds the result up.
            inner = inner.pow(
                _params.presentValueParams.timeStretch.divUp(
                    ONE - _params.presentValueParams.timeStretch
                )
            );
        } else {
            // NOTE: Round the exponent down since this rounds the result up.
            inner = inner.pow(
                _params.presentValueParams.timeStretch.divDown(
                    ONE - _params.presentValueParams.timeStretch
                )
            );
        }

        // NOTE: Round up since this is on the rhs of the final subtraction.
        //
        // derivative = (1 / c) * (
        //                  c * (mu * z_e(x)) ** -t_s +
        //                  (y / z_e) * y(x) ** -t_s  -
        //                  (y / z_e) * (y(x) - dy) ** -t_s
        //              ) * (
        //                  (mu / c) * (k(x) - (y(x) - dy) ** (1 - t_s))
        //              ) ** (t_s / (1 - t_s))
        derivative = derivative.mulDivUp(
            inner,
            _params.presentValueParams.vaultSharePrice
        );

        // derivative = 1 - derivative
        if (ONE >= derivative) {
            derivative = ONE - derivative;
        } else {
            // NOTE: Small rounding errors can result in the derivative being
            // slightly (on the order of a few wei) greater than 1. In this case,
            // we return 0 since we should proceed with Newton's method.
            return (0, true);
        }

        // NOTE: Round down to round the final result down.
        //
        // derivative = derivative * (1 - (zeta / z))
        if (_params.originalShareAdjustment >= 0) {
            derivative = derivative.mulDown(
                ONE -
                    uint256(_params.originalShareAdjustment).divUp(
                        _params.originalShareReserves
                    )
            );
        } else {
            derivative = derivative.mulDown(
                ONE +
                    uint256(-_params.originalShareAdjustment).divDown(
                        _params.originalShareReserves
                    )
            );
        }

        return (derivative, true);
    }
}
