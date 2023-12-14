// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

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
            shareAdjustment = int256(
                uint256(shareReserves).mulDivDown(
                    uint256(_shareAdjustment),
                    _shareReserves
                )
            );
        } else {
            shareAdjustment = -int256(
                uint256(shareReserves).mulDivDown(
                    uint256(-_shareAdjustment),
                    _shareReserves
                )
            );
        }

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
        uint256 sharePrice;
        uint256 initialSharePrice;
        uint256 minimumShareReserves;
        uint256 timeStretch;
        uint256 longsOutstanding;
        uint256 longAverageTimeRemaining;
        uint256 shortsOutstanding;
        uint256 shortAverageTimeRemaining;
    }

    /// @dev Calculates the present value LPs capital in the pool and reverts
    ///      if the value is negative.
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
        // The net curve position is the net of the longs and shorts that are
        // currently tradeable on the curve. Given the amount of outstanding
        // longs `y_l` and shorts `y_s` as well as the average time remaining
        // of outstanding longs `t_l` and shorts `t_s`, we can
        // compute the net curve position as:
        //
        // netCurveTrade = y_l * t_l - y_s * t_s.
        int256 netCurvePosition = int256(
            _params.longsOutstanding.mulDown(_params.longAverageTimeRemaining)
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
                    _params.sharePrice,
                    _params.initialSharePrice
                );
            if (!success) {
                return (0, false);
            }

            // If the max curve trade is greater than the net curve position,
            // then we can close the entire net curve position.
            if (maxCurveTrade >= netCurvePosition_) {
                uint256 netCurveTrade = YieldSpaceMath
                    .calculateSharesOutGivenBondsInDown(
                        effectiveShareReserves,
                        _params.bondReserves,
                        netCurvePosition_,
                        ONE - _params.timeStretch,
                        _params.sharePrice,
                        _params.initialSharePrice
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
                _params.sharePrice,
                _params.initialSharePrice
            );

            // If the max curve trade is greater than the net curve position,
            // then we can close the entire net curve position.
            if (maxCurveTrade >= netCurvePosition_) {
                uint256 netCurveTrade = YieldSpaceMath
                    .calculateSharesInGivenBondsOutUp(
                        effectiveShareReserves,
                        _params.bondReserves,
                        netCurvePosition_,
                        ONE - _params.timeStretch,
                        _params.sharePrice,
                        _params.initialSharePrice
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
                        _params.sharePrice,
                        _params.initialSharePrice
                    );
                return (
                    int256(
                        maxSharePayment +
                            (netCurvePosition_ - maxCurveTrade).divDown(
                                _params.sharePrice
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
                    _params.sharePrice
                )
            ) -
            int256(
                _params.longsOutstanding.mulDivDown(
                    ONE - _params.longAverageTimeRemaining,
                    _params.sharePrice
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
    ///      pool's current idle liquidity.
    /// @param _params The parameters for the distribute excess idle.
    /// @return The amount of withdrawal shares that can be redeemed.
    /// @return The share proceeds the withdrawal pool should receive.
    function calculateDistributeExcessIdle(
        DistributeExcessIdleParams memory _params
    ) internal pure returns (uint256, uint256) {
        // Calculate the maximum amount the share reserves can be debited.
        uint256 originalEffectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                _params.originalShareReserves,
                _params.originalShareAdjustment
            );
        uint256 maxShareReservesDelta = calculateMaxShareReservesDelta(
            _params,
            originalEffectiveShareReserves,
            3 // FIXME: We should pass this in. That let's us use a cheaper version during trades.
        );

        // Calculate the amount of withdrawal shares that can be redeemed given
        // the maximum share reserves delta.  Otherwise, we
        // proceed to calculating the amount of shares that should be paid out
        // to redeem all of the withdrawal shares.
        uint256 withdrawalSharesRedeemed = calculateDistributeExcessIdleWithdrawalSharesRedeemed(
                _params,
                maxShareReservesDelta
            );

        // If none of the withdrawal shares could be redeemed, then we're done
        // and we pay out nothing.
        if (withdrawalSharesRedeemed == 0) {
            return (0, 0);
        }
        // Otherwise if this amount is less than or equal to the amount of
        // withdrawal shares outstanding, then we're done and we pay out the
        // full maximum share reserves delta.
        else if (
            withdrawalSharesRedeemed <= _params.withdrawalSharesTotalSupply
        ) {
            return (withdrawalSharesRedeemed, maxShareReservesDelta);
        }
        // Otherwise, all of the withdrawal shares are redeemed and we need to
        // calculate the amount of shares the withdrawal pool should receive.
        else {
            withdrawalSharesRedeemed = _params.withdrawalSharesTotalSupply;
        }

        // Solve for the share proceeds that hold the LP share price invariant
        // after all of the withdrawal shares are redeemed.
        uint256 shareProceeds = calculateDistributeExcessIdleShareProceeds(
            _params,
            originalEffectiveShareReserves
        );

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

        // Calculate the amount of withdrawal shares that can be redeemed.
        uint256 lpTotalSupply = _params.activeLpTotalSupply +
            _params.withdrawalSharesTotalSupply;
        return
            lpTotalSupply -
            lpTotalSupply.mulDivUp(
                endingPresentValue,
                _params.startingPresentValue
            );
    }

    // FIXME: Todos
    //
    // 1. [ ] Ensure that we're rounding in the right direction.
    //
    /// @dev Calculates the share proceeds to distribute to the withdrawal pool
    ///      assuming that all of the outstanding withdrawal shares will be
    ///      redeemed. The share proceeds are calculated such that the LP share
    ///      price is conserved.
    /// @param _params The parameters for the distribute excess idle calculation.
    /// @param _originalEffectiveShareReserves The original effective share
    ///        reserves.
    /// @return The share proceeds to distribute to the withdrawal pool.
    function calculateDistributeExcessIdleShareProceeds(
        DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves
    ) internal pure returns (uint256) {
        // Calculate the LP total supply.
        uint256 lpTotalSupply = _params.activeLpTotalSupply +
            _params.withdrawalSharesTotalSupply;

        // If the pool is net neutral, we can solve directly.
        if (_params.netCurveTrade == 0) {
            return
                _params.startingPresentValue.mulDivDown(
                    _params.withdrawalSharesTotalSupply,
                    lpTotalSupply
                );
        }

        // We make an initial guess for Newton's method by assuming that the
        // ratio of the share reserves delta to the withdrawal shares
        // outstanding is equal to the LP share price. In reality, the
        // withdrawal pool should receive more than this, but it's a good
        // starting point. The calculation is:
        //
        // x_0 = (PV(0) / l) * w
        uint256 shareProceeds = _params.withdrawalSharesTotalSupply.mulDivDown(
            _params.startingPresentValue,
            lpTotalSupply
        );

        // If the net curve trade is positive, the pool is net long.
        if (_params.netCurveTrade > 0) {
            // FIXME: This is the route that fails at the 1e6 tolerance.
            // Investigate this further to see if we can eek out more precision.
            for (uint256 i = 0; i < SHARE_PROCEEDS_MAX_ITERATIONS; i++) {
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
                (uint256 maxBondAmount, bool success) = YieldSpaceMath
                    .calculateMaxSellBondsInSafe(
                        _params.presentValueParams.shareReserves,
                        _params.presentValueParams.shareAdjustment,
                        _params.presentValueParams.bondReserves,
                        _params.presentValueParams.minimumShareReserves,
                        ONE - _params.presentValueParams.timeStretch,
                        _params.presentValueParams.sharePrice,
                        _params.presentValueParams.initialSharePrice
                    );
                if (!success) {
                    break;
                }
                uint256 derivative;
                if (uint256(_params.netCurveTrade) <= maxBondAmount) {
                    derivative =
                        ONE -
                        calculateSharesOutGivenBondsInDerivative(
                            _params,
                            _originalEffectiveShareReserves,
                            uint256(_params.netCurveTrade)
                        );
                }
                // Otherwise, we can solve directly for the share proceeds.
                else {
                    // FIXME: We need to battle-test this.
                    return
                        calculateDistributeExcessIdleShareProceedsNetLongEdgeCase(
                            _params
                        );
                }

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
                        _params.startingPresentValue.mulDown(
                            _params.activeLpTotalSupply
                        )
                    );
                if (delta > 0) {
                    shareProceeds =
                        shareProceeds +
                        uint256(delta).divDown(
                            derivative.mulDown(lpTotalSupply)
                        );
                } else if (delta < 0) {
                    shareProceeds =
                        shareProceeds -
                        uint256(-delta).divDown(
                            derivative.mulDown(lpTotalSupply)
                        );
                } else {
                    break;
                }
            }
        }
        // Otherwise, the pool is net short.
        else {
            for (uint256 i = 0; i < SHARE_PROCEEDS_MAX_ITERATIONS; i++) {
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
                uint256 derivative = ONE -
                    calculateSharesInGivenBondsOutDerivative(
                        _params,
                        _originalEffectiveShareReserves,
                        uint256(-_params.netCurveTrade)
                    );

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
                        _params.startingPresentValue.mulDown(
                            _params.activeLpTotalSupply
                        )
                    );
                if (delta > 0) {
                    shareProceeds =
                        shareProceeds +
                        uint256(delta).divDown(
                            derivative.mulDown(lpTotalSupply)
                        );
                } else if (delta < 0) {
                    shareProceeds =
                        shareProceeds -
                        uint256(-delta).divDown(
                            derivative.mulDown(lpTotalSupply)
                        );
                } else {
                    break;
                }
            }
        }

        return shareProceeds;
    }

    // FIXME: Natspec.
    //
    // FIXME: Find a better name for this.
    //
    // FIXME: Make sure we're testing this.
    //
    // FIXME: This is never being called. Do we need it?
    function calculateDistributeExcessIdleShareProceedsNetLongEdgeCase(
        DistributeExcessIdleParams memory _params
    ) internal pure returns (uint256) {
        // FIXME: Document this.
        _params.presentValueParams.shareReserves = _params
            .originalShareReserves;
        _params.presentValueParams.shareAdjustment = _params
            .originalShareAdjustment;
        _params.presentValueParams.bondReserves = _params.originalBondReserves;
        int256 netFlatTrade = calculateNetFlatTrade(_params.presentValueParams);
        uint256 inner;
        if (netFlatTrade >= 0) {
            inner =
                _params.startingPresentValue.mulDivUp(
                    _params.activeLpTotalSupply,
                    _params.activeLpTotalSupply +
                        _params.withdrawalSharesTotalSupply
                ) -
                uint256(netFlatTrade);
        } else {
            inner =
                _params.startingPresentValue.mulDivUp(
                    _params.activeLpTotalSupply,
                    _params.activeLpTotalSupply +
                        _params.withdrawalSharesTotalSupply
                ) +
                uint256(-netFlatTrade);
        }

        // FIXME: This should only ever be needed when zeta is less than 0.
        if (_params.originalShareAdjustment > 0) {
            return
                _params.originalShareReserves -
                _params.originalShareReserves.mulDivUp(
                    inner,
                    uint256(_params.originalShareAdjustment)
                );
        } else if (_params.originalShareAdjustment < 0) {
            return
                _params.originalShareReserves +
                _params.originalShareReserves.mulDivUp(
                    inner,
                    uint256(-_params.originalShareAdjustment)
                );
        }

        // FIXME: Explain why we're returning 0 here.
        return 0;
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
        if (lpSharePriceAfter < lpSharePriceBefore) {
            return false;
        }
        return
            lpSharePriceAfter >= lpSharePriceBefore &&
            lpSharePriceAfter <=
            lpSharePriceBefore.mulDown(ONE + SHARE_PROCEEDS_MIN_TOLERANCE);
    }

    // FIXME: Todos
    //
    // 1. [ ] Ensure that we're rounding in the right direction.
    // 2. [ ] Use a smaller numbers of iterations when calculating the maximum
    //       share reserves delta.
    // 3. [ ] Add a configurable tolerance to short-circuit.
    //
    /// @dev Calculates the upper bound on the share proceeds of distributing
    ///      excess idle. When the pool is net long or net neutral, the upper
    ///      bound is the amount of idle liquidity. When the pool is net short,
    ///      the upper bound is the share reserves delta that results in the
    ///      maximum amount of bonds that can be purchased being equal to the
    ///      net short position.
    /// @param _params The parameters for the distribute excess idle calculation.
    /// @param _originalEffectiveShareReserves The original effective share
    ///        reserves.
    /// @param _maxIterations The maximum number of iterations to perform.
    /// @return maxShareReservesDelta The upper bound on the share proceeds.
    function calculateMaxShareReservesDelta(
        DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves,
        uint256 _maxIterations
    ) internal pure returns (uint256 maxShareReservesDelta) {
        // If the net curve position is zero or net long, then the maximum
        // share reserves delta is equal to the pool's idle.
        if (_params.netCurveTrade >= 0) {
            return _params.idle;
        }
        uint256 netCurveTrade = uint256(-_params.netCurveTrade);

        // Check to see if the max bond amount is greater than the net curve
        // trade if all of the idle is removed from the pool. If so, then we're
        // done.
        {
            // Calculate the maximum amount of bonds that can be purchased after
            // removing all of the idle liquidity.
            (
                _params.presentValueParams.shareReserves,
                _params.presentValueParams.shareAdjustment,
                _params.presentValueParams.bondReserves
            ) = calculateUpdateLiquidity(
                _params.originalShareReserves,
                _params.originalShareAdjustment,
                _params.originalBondReserves,
                _params.presentValueParams.minimumShareReserves,
                -int256(_params.idle)
            );
            uint256 maxBondAmount = YieldSpaceMath.calculateMaxBuyBondsOut(
                HyperdriveMath.calculateEffectiveShareReserves(
                    _params.presentValueParams.shareReserves,
                    _params.presentValueParams.shareAdjustment
                ),
                _params.presentValueParams.bondReserves,
                ONE - _params.presentValueParams.timeStretch,
                _params.presentValueParams.sharePrice,
                _params.presentValueParams.initialSharePrice
            );

            // If the maximum amount of bonds that can be purchased is greater
            // than the net curve trade, then the max share delta is equal to
            // pool's idle capital.
            if (maxBondAmount >= netCurveTrade) {
                return _params.idle;
            }
        }

        // Calculate an initial guess for the max share delta.
        uint256 maybeMaxShareReservesDelta = calculateMaxShareReservesDeltaInitialGuess(
                _params,
                _originalEffectiveShareReserves,
                netCurveTrade
            );

        // Proceed with Newton's method for a few iterations.
        for (uint256 i = 0; i < _maxIterations; i++) {
            // Calculate the maximum amount of bonds that can be purchased after
            // removing the maximum share reserves delta.
            (
                _params.presentValueParams.shareReserves,
                _params.presentValueParams.shareAdjustment,
                _params.presentValueParams.bondReserves
            ) = calculateUpdateLiquidity(
                _params.originalShareReserves,
                _params.originalShareAdjustment,
                _params.originalBondReserves,
                _params.presentValueParams.minimumShareReserves,
                -int256(maybeMaxShareReservesDelta)
            );
            uint256 maxBondAmount = YieldSpaceMath.calculateMaxBuyBondsOut(
                HyperdriveMath.calculateEffectiveShareReserves(
                    _params.presentValueParams.shareReserves,
                    _params.presentValueParams.shareAdjustment
                ),
                _params.presentValueParams.bondReserves,
                ONE - _params.presentValueParams.timeStretch,
                _params.presentValueParams.sharePrice,
                _params.presentValueParams.initialSharePrice
            );

            // Calculate the derivative of `calculateMaxBuyBondsOut(x)` at the
            // current guess. We break if the derivative can't be computed.
            (
                uint256 derivative,
                bool success
            ) = calculateMaxBuyBondsOutDerivativeSafe(
                    _params,
                    _originalEffectiveShareReserves
                );
            if (!success) {
                break;
            }

            // If the maximum amount of bonds that can be purchased is greater
            // than the net curve trade, then we're below the optimal point.
            if (maxBondAmount > netCurveTrade) {
                // We calculate the updated max share reserves delta `x_n+1` by
                // proceeding with Newton's method. This is given by:
                //
                // x_n+1 = x_n - F(x_n) / F'(x_n)
                //
                // where our objective function `F(x)` is:
                //
                // F(x) = calculateMaxBuyBondsOut(x) - netCurveTrade
                //
                // The derivative of `calculateMaxBuyBondsOut(x)` is negative,
                // but we use the negation of the derivative to avoid integer
                // underflows. With this in mind, we add the delta instead of
                // subtracting.
                maxShareReservesDelta = maybeMaxShareReservesDelta;
                maybeMaxShareReservesDelta =
                    maybeMaxShareReservesDelta +
                    (maxBondAmount - netCurveTrade).divDown(derivative);
            }
            // If the maximum amount of bonds that can be purchased is greater
            // than the net curve trade, then we're above the optimal point.
            else if (maxBondAmount < netCurveTrade) {
                // We calculate the updated max share reserves delta `x_n+1` by
                // proceeding with Newton's method. This is given by:
                //
                // x_n+1 = x_n - F(x_n) / F'(x_n)
                //
                // where our objective function `F(x)` is:
                //
                // F(x) = netCurveTrade - calculateMaxBuyBondsOut(x)
                //
                // The derivative of `calculateMaxBuyBondsOut(x)` is negative,
                // but we use the negation of the derivative to avoid integer
                // underflows. With this in mind, we subtract the delta instead
                // of adding.
                uint256 delta = (netCurveTrade - maxBondAmount).divDown(
                    derivative
                );
                if (delta >= maybeMaxShareReservesDelta) {
                    break;
                }
                maybeMaxShareReservesDelta = maybeMaxShareReservesDelta - delta;
            } else {
                break;
            }

            // If the max share reserves delta is greater than the idle, then
            // we clamp back to the pool's idle.
            if (maybeMaxShareReservesDelta > _params.idle) {
                maybeMaxShareReservesDelta = _params.idle;
            }
        }

        // Check to see if we've found a better max share reserves delta.
        if (maybeMaxShareReservesDelta != maxShareReservesDelta) {
            (
                _params.presentValueParams.shareReserves,
                _params.presentValueParams.shareAdjustment,
                _params.presentValueParams.bondReserves
            ) = calculateUpdateLiquidity(
                _params.originalShareReserves,
                _params.originalShareAdjustment,
                _params.originalBondReserves,
                _params.presentValueParams.minimumShareReserves,
                -int256(maybeMaxShareReservesDelta)
            );
            uint256 maxBondAmount = YieldSpaceMath.calculateMaxBuyBondsOut(
                HyperdriveMath.calculateEffectiveShareReserves(
                    _params.presentValueParams.shareReserves,
                    _params.presentValueParams.shareAdjustment
                ),
                _params.presentValueParams.bondReserves,
                ONE - _params.presentValueParams.timeStretch,
                _params.presentValueParams.sharePrice,
                _params.presentValueParams.initialSharePrice
            );
            if (maxBondAmount >= netCurveTrade) {
                maxShareReservesDelta = maybeMaxShareReservesDelta;
            }
        }

        return maxShareReservesDelta;
    }

    // FIXME: Make sure that we round consistently.
    //
    /// @dev Calculates the initial guess to use for iteratively solving for the
    ///      maximum share reserves delta. The maximum amount of bonds that can
    ///      be purchased as a function of the shares removed from the share
    ///      reserves `x` is calculated as:
    ///
    ///      y_max(x) = y(x) - (k(x) / ((c / mu) + 1)) ** (1 / (1 - t_s))
    ///
    ///      Our initial guess should underestimate this value since we want
    ///      to approach the optimal value from below. We can derive our initial
    ///      guess by solving for `x_0` in the following equation:
    ///
    ///      netCurveTrade = y(x_0) - (k(0) / ((c / mu) + 1)) ** (1 / (1 - t_s))
    ///                                =>
    ///      x_0 = z - ((
    ///                netCurveTrade + (k(0) / ((c / mu) + 1)) ** (1 / (1 - t_s))
    ///            ) / ((y / z_e) * (1 - zeta / z)))
    ///
    /// @param _params The parameters for the distribute excess idle calculation.
    /// @param _originalEffectiveShareReserves The original effective share
    ///        reserves.
    /// @param _netCurveTrade The net curve trade.
    /// @return The initial guess for the maximum share reserves delta.
    function calculateMaxShareReservesDeltaInitialGuess(
        DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves,
        uint256 _netCurveTrade
    ) internal pure returns (uint256) {
        uint256 lhs = _netCurveTrade +
            YieldSpaceMath
                .kDown(
                    _originalEffectiveShareReserves,
                    _params.originalBondReserves,
                    ONE - _params.presentValueParams.timeStretch,
                    _params.presentValueParams.sharePrice,
                    _params.presentValueParams.initialSharePrice
                )
                .divDown(
                    _params.presentValueParams.sharePrice.divUp(
                        _params.presentValueParams.initialSharePrice
                    ) + ONE
                )
                .pow(ONE.divDown(ONE - _params.presentValueParams.timeStretch));
        if (_params.originalShareAdjustment >= 0) {
            lhs = lhs.divDown(
                _params.originalBondReserves.mulDivUp(
                    ONE -
                        uint256(_params.originalShareAdjustment).divUp(
                            _params.originalShareReserves
                        ),
                    _originalEffectiveShareReserves
                )
            );
        } else {
            lhs = lhs.divDown(
                _params.originalBondReserves.mulDivUp(
                    ONE +
                        uint256(-_params.originalShareAdjustment).divUp(
                            _params.originalShareReserves
                        ),
                    _originalEffectiveShareReserves
                )
            );
        }
        return _params.originalShareReserves - lhs;
    }

    // FIXME: Todos
    //
    // 1. [ ] Check that we're rounding in the right direction.
    // 2. [x] Double check this calculation.
    //
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
    /// @param _params The parameters for the calculation.
    /// @param _originalEffectiveShareReserves The original effective share
    ///        reserves.
    /// @param _bondAmount The amount of bonds to sell.
    /// @return The derivative.
    function calculateSharesOutGivenBondsInDerivative(
        DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves,
        uint256 _bondAmount
    ) internal pure returns (uint256) {
        uint256 effectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                _params.presentValueParams.shareReserves,
                _params.presentValueParams.shareAdjustment
            );
        uint256 k = YieldSpaceMath.kDown(
            effectiveShareReserves,
            _params.presentValueParams.bondReserves,
            ONE - _params.presentValueParams.timeStretch,
            _params.presentValueParams.sharePrice,
            _params.presentValueParams.initialSharePrice
        );
        uint256 derivative = _params.presentValueParams.sharePrice.divDown(
            _params
                .presentValueParams
                .initialSharePrice
                .mulUp(effectiveShareReserves)
                .pow(_params.presentValueParams.timeStretch)
        ) +
            _params.originalBondReserves.divDown(
                _originalEffectiveShareReserves.mulUp(
                    _params.presentValueParams.bondReserves.pow(
                        _params.presentValueParams.timeStretch
                    )
                )
            ) -
            _params.originalBondReserves.divDown(
                _originalEffectiveShareReserves.mulUp(
                    (_params.presentValueParams.bondReserves + _bondAmount).pow(
                        _params.presentValueParams.timeStretch
                    )
                )
            );
        derivative = derivative.mulDivDown(
            _params
                .presentValueParams
                .initialSharePrice
                .mulDivDown(
                    k -
                        (_params.presentValueParams.bondReserves + _bondAmount)
                            .pow(ONE - _params.presentValueParams.timeStretch),
                    _params.presentValueParams.sharePrice
                )
                .pow(
                    _params.presentValueParams.timeStretch.divDown(
                        ONE - _params.presentValueParams.timeStretch
                    )
                ),
            _params.presentValueParams.sharePrice
        );
        if (ONE >= derivative) {
            derivative = ONE - derivative;
        } else {
            // NOTE: Small rounding errors can result in the derivative being
            // slightly (on the order of a few wei) greater than 1. In this case,
            // we return 0 since we should proceed with Newton's method.
            return 0;
        }
        if (_params.originalShareAdjustment >= 0) {
            derivative = derivative.mulDown(
                ONE -
                    uint256(_params.originalShareAdjustment).divDown(
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

        return derivative;
    }

    // FIXME: Todos
    //
    // 1. [ ] Check that we're rounding in the right direction.
    // 2. [ ] Double check this calculation.
    //
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
    /// @param _params The parameters for the calculation.
    /// @param _originalEffectiveShareReserves The original effective share
    ///        reserves.
    /// @param _bondAmount The amount of bonds to sell.
    /// @return The derivative.
    function calculateSharesInGivenBondsOutDerivative(
        DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves,
        uint256 _bondAmount
    ) internal pure returns (uint256) {
        uint256 effectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                _params.presentValueParams.shareReserves,
                _params.presentValueParams.shareAdjustment
            );
        uint256 k = YieldSpaceMath.kDown(
            effectiveShareReserves,
            _params.presentValueParams.bondReserves,
            ONE - _params.presentValueParams.timeStretch,
            _params.presentValueParams.sharePrice,
            _params.presentValueParams.initialSharePrice
        );
        uint256 derivative = _params.presentValueParams.sharePrice.divDown(
            _params
                .presentValueParams
                .initialSharePrice
                .mulUp(effectiveShareReserves)
                .pow(_params.presentValueParams.timeStretch)
        ) +
            _params.originalBondReserves.divDown(
                _originalEffectiveShareReserves.mulUp(
                    _params.presentValueParams.bondReserves.pow(
                        _params.presentValueParams.timeStretch
                    )
                )
            ) -
            _params.originalBondReserves.divDown(
                _originalEffectiveShareReserves.mulUp(
                    (_params.presentValueParams.bondReserves - _bondAmount).pow(
                        _params.presentValueParams.timeStretch
                    )
                )
            );
        derivative = derivative.mulDivDown(
            _params
                .presentValueParams
                .initialSharePrice
                .mulDivDown(
                    k -
                        (_params.presentValueParams.bondReserves - _bondAmount)
                            .pow(ONE - _params.presentValueParams.timeStretch),
                    _params.presentValueParams.sharePrice
                )
                .pow(
                    _params.presentValueParams.timeStretch.divDown(
                        ONE - _params.presentValueParams.timeStretch
                    )
                ),
            _params.presentValueParams.sharePrice
        );
        if (ONE >= derivative) {
            derivative = ONE - derivative;
        } else {
            // NOTE: Small rounding errors can result in the derivative being
            // slightly (on the order of a few wei) greater than 1. In this case,
            // we return 0 since we should proceed with Newton's method.
            return 0;
        }
        if (_params.originalShareAdjustment >= 0) {
            derivative = derivative.mulDown(
                ONE -
                    uint256(_params.originalShareAdjustment).divDown(
                        _params.originalShareReserves
                    )
            );
        } else {
            derivative = derivative.mulUp(
                ONE +
                    uint256(-_params.originalShareAdjustment).divUp(
                        _params.originalShareReserves
                    )
            );
        }
        return derivative;
    }

    // FIXME: Todos
    //
    // 1. [ ] Check that we're rounding in the right direction.
    //
    /// @dev Calculates the derivative of `calculateMaxBuyBondsOut`. This
    ///      derivative is given by:
    ///
    ///      derivative = - (1 - zeta / z) * (
    ///          (y / z_e) - ((
    ///              c * (mu * z_e(x)) ** -t_s +
    ///              (y / z_e) * y(x) ** -t_s
    ///          ) * (
    ///              k(x) / ((c / mu) + 1)
    ///          ) ** (t_s / (1 - t_s))) * (
    ///              1 / ((c / mu) + 1)
    ///          ) ** (1 / (1 - t_s))
    ///      )
    ///
    ///      This function actually calculates the negatation of the derivative
    ///      to avoid integer underflows.
    /// @param _params The parameters for the calculation.
    /// @param _originalEffectiveShareReserves The original effective share
    ///        reserves.
    /// @return The derivative.
    /// @return A flag indicating when the derivative couldn't be computed.
    function calculateMaxBuyBondsOutDerivativeSafe(
        DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves
    ) internal pure returns (uint256, bool) {
        uint256 effectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                _params.presentValueParams.shareReserves,
                _params.presentValueParams.shareAdjustment
            );
        uint256 derivative = _params.presentValueParams.sharePrice.divDown(
            _params
                .presentValueParams
                .initialSharePrice
                .mulUp(effectiveShareReserves)
                .pow(_params.presentValueParams.timeStretch)
        ) +
            _params.originalBondReserves.divDown(
                _originalEffectiveShareReserves.mulUp(
                    _params.presentValueParams.bondReserves.pow(
                        _params.presentValueParams.timeStretch
                    )
                )
            );
        derivative = derivative.mulDown(
            YieldSpaceMath
                .kDown(
                    effectiveShareReserves,
                    _params.presentValueParams.bondReserves,
                    ONE - _params.presentValueParams.timeStretch,
                    _params.presentValueParams.sharePrice,
                    _params.presentValueParams.initialSharePrice
                )
                .pow(
                    // TODO: Account for rounding here.
                    _params.presentValueParams.timeStretch.divDown(
                        ONE - _params.presentValueParams.timeStretch
                    )
                )
        );
        derivative = derivative.divDown(
            (_params.presentValueParams.sharePrice.divUp(
                _params.presentValueParams.initialSharePrice
            ) + ONE).pow(
                    // TODO: Account for rounding here.
                    ONE.divDown(ONE - _params.presentValueParams.timeStretch)
                )
        );
        uint256 delta = _params.originalBondReserves.divDown(
            _originalEffectiveShareReserves
        );
        if (derivative <= delta) {
            derivative = delta - derivative;
        } else {
            // Since the calculation would underflow, we return 0 and a flag
            // indicating that the derivative couldn't be computed.
            return (0, false);
        }
        if (_params.originalShareAdjustment >= 0) {
            derivative = (ONE -
                uint256(_params.originalShareAdjustment).divDown(
                    _params.originalShareReserves
                )).mulDown(derivative);
        } else {
            derivative = (ONE +
                uint256(-_params.originalShareAdjustment).divDown(
                    _params.originalShareReserves
                )).mulDown(derivative);
        }
        return (derivative, true);
    }
}
