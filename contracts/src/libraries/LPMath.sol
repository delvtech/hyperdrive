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
        // zeta_old / z_old = zeta_new / z_new => zeta_new = zeta_old * (z_new / z_old)
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

    /// @dev Calculates the present value LPs capital in the pool.
    /// @param _params The parameters for the present value calculation.
    /// @return The present value of the pool.
    function calculatePresentValue(
        PresentValueParams memory _params
    ) internal pure returns (uint256) {
        // We calculate the LP present value by simulating the closing of all
        // of the outstanding long and short positions and applying this impact
        // on the share reserves. The present value is the share reserves after
        // the impact of the trades minus the minimum share reserves:
        //
        // PV = z + net_c + net_f - z_min
        int256 presentValue = int256(_params.shareReserves) +
            calculateNetCurveTrade(_params) +
            calculateNetFlatTrade(_params) -
            int256(_params.minimumShareReserves);

        // If the present value is negative, we revert.
        if (presentValue < 0) {
            revert IHyperdrive.NegativePresentValue();
        }

        return uint256(presentValue);
    }

    /// @dev Calculates the result of closing the net curve position.
    /// @param _params The parameters for the present value calculation.
    /// @return The impact of closing the net curve position on the share
    ///         reserves.
    function calculateNetCurveTrade(
        PresentValueParams memory _params
    ) internal pure returns (int256) {
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
            // YieldSpace.
            uint256 maxCurveTrade = YieldSpaceMath.calculateMaxSellBondsIn(
                effectiveShareReserves,
                _params.bondReserves,
                _params.minimumShareReserves,
                ONE - _params.timeStretch,
                _params.sharePrice,
                _params.initialSharePrice
            );

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
                return -int256(netCurveTrade);
            }
            // Otherwise, we can only close part of the net curve position.
            // Since the spot price is approximately zero after closing the
            // entire net curve position, we mark any remaining bonds to zero.
            else {
                return
                    -int256(
                        effectiveShareReserves - _params.minimumShareReserves
                    );
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
                return int256(netCurveTrade);
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
                return
                    int256(
                        maxSharePayment +
                            (netCurvePosition_ - maxCurveTrade).divDown(
                                _params.sharePrice
                            )
                    );
            }
        }

        return 0;
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
        uint256 originalShareReserves;
        int256 originalShareAdjustment;
        uint256 originalBondReserves;
        uint256 activeLpTotalSupply;
        uint256 withdrawalSharesTotalSupply;
        uint256 idle;
    }

    // FIXME: Benchmark this.
    //
    /// @dev Calculates the amount of withdrawal shares that can be redeemed and
    ///      the share proceeds the withdrawal pool should receive given the
    ///      pool's current idle liquidity.
    /// @param _params The parameters for the distribute excess idle.
    /// @return The amount of withdrawal shares that can be redeemed.
    /// @return The share proceeds the withdrawal pool should receive.
    function calculateDistributeExcessIdle(
        DistributeExcessIdleParams memory _params
    ) internal pure returns (uint256, uint256) {
        // If there are no withdrawal shares or idle liquidity, then there is
        // nothing to do.
        if (_params.withdrawalSharesTotalSupply == 0 || _params.idle == 0) {
            return (0, 0);
        }

        // Calculate the maximum amount the share reserves can be debited.
        uint256 originalEffectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                _params.originalShareReserves,
                _params.originalShareAdjustment
            );
        int256 netCurveTrade = int256(
            _params.presentValueParams.longsOutstanding.mulDown(
                _params.presentValueParams.shortAverageTimeRemaining
            )
        ) -
            int256(
                _params.presentValueParams.shortsOutstanding.mulDown(
                    _params.presentValueParams.longAverageTimeRemaining
                )
            );
        uint256 maxShareReservesDelta = calculateMaxShareReservesDelta(
            _params,
            originalEffectiveShareReserves,
            netCurveTrade
        );

        // Calculate the amount of withdrawal shares that can be redeemed given
        // the maximum share reserves delta.  Otherwise, we
        // proceed to calculating the amount of shares that should be paid out
        // to redeem all of the withdrawal shares.
        uint256 withdrawalSharesRedeemed = calculateDistributeExcessIdleWithdrawalSharesRedeemed(
                _params,
                maxShareReservesDelta
            );

        // If this amount is less than or equal to the amount of withdrawal
        // shares outstanding, then we're done and we pay out the full maximum
        // share reserves delta.
        if (withdrawalSharesRedeemed >= _params.withdrawalSharesTotalSupply) {
            return (maxShareReservesDelta, withdrawalSharesRedeemed);
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
            originalEffectiveShareReserves,
            netCurveTrade
        );

        return (withdrawalSharesRedeemed, shareProceeds);
    }

    // FIXME: This is *really* expensive. With 3 iterations, the sad path is
    // around 60k gas. With 4 iterations, it's around 80k gas.
    //
    // FIXME: How accurate does this actually need to be? One thought here is
    //        that there are two branches here that are realistic. One is that
    //        we can pay out all of the withdrawal shares even with an
    //        underestimate. In that case, further iterations don't buy us
    //        anything, and are just wasting effort. In the other case, we
    //        can't pay out all of the withdrawal shares even with an
    //        overestimate. In that case, further iterations would result in
    //        more withdrawal shares being redeemed; however, these withdrawal
    //        shares would also be redeemed in a subsequent transaction.
    //
    //        One good way to split the difference is to use an even simpler
    //        approximation that is much cheaper to compute. This will be
    //        ammortized over the course of many trades. If LPs want to be able
    //        to withdraw faster, they can run the calculation with more
    //        iterations when they call `redeeemWithdrawalShares` (we may want
    //        to pass an option here to prevent users from calling this
    //        erroneously).
    //
    /// @dev Calculates the upper bound on the share proceeds of distributing
    ///      excess idle. When the pool is net long or net neutral, the upper
    ///      bound is the amount of idle liquidity. When the pool is net short,
    ///      the upper bound is the share reserves delta that results in the
    ///      maximum amount of bonds that can be purchased being equal to the
    ///      net short position.
    /// @param _params The parameters for the distribute excess idle calculation.
    /// @param _netCurveTrade The net curve trade.
    /// @return The upper bound on the share proceeds.
    function calculateMaxShareReservesDelta(
        DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves,
        int256 _netCurveTrade
    ) internal pure returns (uint256) {
        // If the net curve position is zero or net long, then the maximum
        // share reserves delta is equal to the pool's idle.
        if (_netCurveTrade >= 0) {
            return _params.idle;
        }
        uint256 netCurveTrade = uint256(-_netCurveTrade);

        // FIXME: Considering the costs of this function as well as the pros and
        // cons of really computing this accurately, it may be better to use a
        // simple surrogate function for this (like the Newton's guess) and be
        // done with it. Before making this call, it's worth benchmarking this
        // check to see how much we're spending on it.
        //
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
        uint256 maxShareReservesDelta = calculateMaxShareReservesDeltaInitialGuess(
                _params,
                _originalEffectiveShareReserves,
                netCurveTrade
            );

        // Proceed with Newton's method for a few iterations.
        for (uint256 i = 0; i < 3; i++) {
            (
                _params.presentValueParams.shareReserves,
                _params.presentValueParams.shareAdjustment,
                _params.presentValueParams.bondReserves
            ) = calculateUpdateLiquidity(
                _params.originalShareReserves,
                _params.originalShareAdjustment,
                _params.originalBondReserves,
                _params.presentValueParams.minimumShareReserves,
                -int256(maxShareReservesDelta)
            );
            maxShareReservesDelta =
                maxShareReservesDelta +
                (YieldSpaceMath.calculateMaxBuyBondsOut(
                    HyperdriveMath.calculateEffectiveShareReserves(
                        _params.presentValueParams.shareReserves,
                        _params.presentValueParams.shareAdjustment
                    ),
                    _params.presentValueParams.bondReserves,
                    ONE - _params.presentValueParams.timeStretch,
                    _params.presentValueParams.sharePrice,
                    _params.presentValueParams.initialSharePrice
                ) - netCurveTrade).divDown(
                        calculateMaxBuyBondsOutDerivative(
                            _params,
                            _originalEffectiveShareReserves
                        )
                    );
        }

        return maxShareReservesDelta;
    }

    // FIXME: Add the ASCII math to the Natspec.
    //
    /// @dev Calculates the initial guess to use for iteratively solving for the
    ///      maximum share reserves delta.
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
        // FIXME: Document this and add ASCII math.
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

    // FIXME: Add the math in this comment.
    //
    /// @dev Calculates the amount of withdrawal shares that can be redeemed
    ///      given an amount of shares to remove from the share reserves.
    /// @param _params The parameters for the present value calculation.
    /// @param _shareReservesDelta The amount of shares to remove from the
    ///        share reserves.
    /// @return The amount of withdrawal shares that can be redeemed.
    function calculateDistributeExcessIdleWithdrawalSharesRedeemed(
        DistributeExcessIdleParams memory _params,
        uint256 _shareReservesDelta
    ) internal pure returns (uint256) {
        // Calculate the starting present value.
        uint256 startingPresentValue;
        {
            _params.presentValueParams.shareReserves = _params
                .originalShareReserves;
            _params.presentValueParams.shareAdjustment = _params
                .originalShareAdjustment;
            _params.presentValueParams.bondReserves = _params
                .originalBondReserves;
            startingPresentValue = calculatePresentValue(
                _params.presentValueParams
            );
        }

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
        uint256 endingPresentValue = calculatePresentValue(
            _params.presentValueParams
        );

        // Calculate the amount of withdrawal shares that can be redeemed with
        // the maximum share reserves delta.
        return
            (ONE - endingPresentValue.divDown(startingPresentValue)).mulDown(
                _params.activeLpTotalSupply
            );
    }

    // FIXME: Todos
    //
    // 1. [ ] Document the body of this function.
    // 2. [ ] Ensure that we're rounding in the right direction.
    // 3. [ ] Add a tolerance parameter or constant.
    //     - [ ] If the tolerance after all is said and done is exceeded, revert
    //           (for now -- we don't want this in prod).
    //     - [ ] If we're under the tolerance, we should return early. We may
    //           want a stricter tolerance for this than the acceptable
    //           tolerance.
    //
    /// @dev Calculates the share proceeds to distribute to the withdrawal pool
    ///      assuming that all of the outstanding withdrawal shares will be
    ///      redeemed. The share proceeds are calculated such that the LP share
    ///      price is conserved.
    /// @param _params The parameters for the distribute excess idle calculation.
    /// @param _originalEffectiveShareReserves The original effective share
    ///        reserves.
    /// @param _netCurveTrade The net curve trade.
    /// @return The share proceeds to distribute to the withdrawal pool.
    function calculateDistributeExcessIdleShareProceeds(
        DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves,
        int256 _netCurveTrade
    ) internal pure returns (uint256) {
        // Calculate the starting present value and LP total supply.
        uint256 startingPresentValue;
        {
            _params.presentValueParams.shareReserves = _params
                .originalShareReserves;
            _params.presentValueParams.shareAdjustment = _params
                .originalShareAdjustment;
            _params.presentValueParams.bondReserves = _params
                .originalBondReserves;
            startingPresentValue = calculatePresentValue(
                _params.presentValueParams
            );
        }
        uint256 lpTotalSupply = _params.activeLpTotalSupply +
            _params.withdrawalSharesTotalSupply;

        // If the pool is net neutral, we can solve directly.
        if (_netCurveTrade == 0) {
            return
                (ONE - _params.activeLpTotalSupply.divDown(lpTotalSupply))
                    .mulDown(startingPresentValue);
        }

        // We make an initial guess for Newton's method by assuming that the
        // ratio of the share reserves delta to the withdrawal shares
        // outstanding is equal to the LP share price. In reality, the
        // withdrawal pool should receive more than this, but it's a good
        // starting point.
        uint256 shareProceeds = _params.withdrawalSharesTotalSupply.mulDivDown(
            startingPresentValue,
            _params.activeLpTotalSupply + _params.withdrawalSharesTotalSupply
        );

        // If the net curve trade is positive, the pool is net long.
        if (_netCurveTrade > 0) {
            // FIXME: Use a constant for the loop iterations.
            for (uint256 i = 0; i < 3; i++) {
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

                // If the net curve trade is less than or equal to the maximum
                // amount of bonds that can be sold with this share proceeds, we
                // can calculate the derivative using the derivative of
                // `calculateSharesOutGivenBondsIn`.
                uint256 derivative;
                if (
                    uint256(_netCurveTrade) <=
                    YieldSpaceMath.calculateMaxSellBondsIn(
                        HyperdriveMath.calculateEffectiveShareReserves(
                            _params.presentValueParams.shareReserves,
                            _params.presentValueParams.shareAdjustment
                        ),
                        _params.presentValueParams.bondReserves,
                        _params.presentValueParams.minimumShareReserves,
                        ONE - _params.presentValueParams.timeStretch,
                        _params.presentValueParams.sharePrice,
                        _params.presentValueParams.initialSharePrice
                    )
                ) {
                    derivative =
                        ONE +
                        calculateSharesOutGivenBondsInDerivative(
                            _params,
                            _originalEffectiveShareReserves,
                            uint256(_netCurveTrade)
                        );
                }
                // FIXME: If we get into this regime, we should be able to solve
                // directly.
                //
                // Otherwise, we calculate the derivative using the derivative
                // of `calculateMaxSellSharesOut`.
                else {
                    derivative =
                        ONE +
                        calculateMaxSellSharesOutDerivative(_params);
                }

                // FIXME: Explain this math.
                shareProceeds =
                    shareProceeds +
                    (presentValue.mulDown(lpTotalSupply) -
                        startingPresentValue.mulDown(
                            _params.activeLpTotalSupply
                        )).divDown(derivative.mulDown(lpTotalSupply));
            }
        }
        // Otherwise, the pool is net short.
        else {
            // FIXME: Use a constant for the loop iterations.
            for (uint256 i = 0; i < 3; i++) {
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

                // If the net curve trade is less than or equal to the maximum
                // amount of bonds that can be sold with this share proceeds, we
                // can calculate the derivative using the derivative of
                // `calculateSharesOutGivenBondsIn`.
                uint256 derivative = ONE +
                    calculateSharesInGivenBondsOutDerivative(
                        _params,
                        _originalEffectiveShareReserves,
                        uint256(-_netCurveTrade)
                    );

                // FIXME: Double check this. Are the signs correct?
                //
                // FIXME: Document this.
                shareProceeds =
                    shareProceeds +
                    (presentValue.mulDown(lpTotalSupply) -
                        startingPresentValue.mulDown(
                            _params.activeLpTotalSupply
                        )).divDown(derivative.mulDown(lpTotalSupply));
            }
        }

        return shareProceeds;
    }

    // FIXME: Todos
    //
    // 1. [ ] Document this body of this function.
    // 2. [ ] Check that we're rounding in the right direction.
    // 3. [ ] Double check this calculation.
    //
    /// @dev Calculates the derivative of `calculateSharesOutGivenBondsIn`.
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
        derivative =
            ONE -
            derivative.mulDivDown(
                _params
                    .presentValueParams
                    .initialSharePrice
                    .mulDivDown(
                        YieldSpaceMath.kDown(
                            effectiveShareReserves,
                            _params.presentValueParams.bondReserves,
                            ONE - _params.presentValueParams.timeStretch,
                            _params.presentValueParams.sharePrice,
                            _params.presentValueParams.initialSharePrice
                        ) -
                            (_params.presentValueParams.bondReserves +
                                _bondAmount).pow(
                                    ONE - _params.presentValueParams.timeStretch
                                ),
                        _params.presentValueParams.sharePrice
                    )
                    .pow(
                        _params.presentValueParams.timeStretch.divDown(
                            ONE - _params.presentValueParams.timeStretch
                        )
                    ),
                _params.presentValueParams.sharePrice
            );
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
    // 1. [ ] Document this body of this function.
    // 2. [ ] Check that we're rounding in the right direction.
    // 3. [ ] Double check this calculation.
    // 4. [ ] Add ASCII math.
    //
    /// @dev Calculates the derivative of `calculateSharesInGivenBondsOut`.
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
        derivative =
            ONE -
            derivative.mulDivDown(
                _params
                    .presentValueParams
                    .initialSharePrice
                    .mulDivDown(
                        k -
                            (_params.presentValueParams.bondReserves -
                                _bondAmount).pow(
                                    ONE - _params.presentValueParams.timeStretch
                                ),
                        _params.presentValueParams.sharePrice
                    )
                    .pow(
                        _params.presentValueParams.timeStretch.divDown(
                            ONE - _params.presentValueParams.timeStretch
                        )
                    ),
                _params.presentValueParams.sharePrice
            );
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
    // 1. [ ] Document this body of this function.
    // 2. [ ] Check that we're rounding in the right direction.
    // 3. [ ] Double check this calculation.
    // 4. [ ] Add ASCII math.
    //
    /// @dev Calculates the derivative of `calculateMaxBuyBondsOut`.
    /// @param _params The parameters for the calculation.
    /// @param _originalEffectiveShareReserves The original effective share
    ///        reserves.
    /// @return The derivative.
    function calculateMaxBuyBondsOutDerivative(
        DistributeExcessIdleParams memory _params,
        uint256 _originalEffectiveShareReserves
    ) internal pure returns (uint256) {
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
                .divDown(
                    _params.presentValueParams.sharePrice.divUp(
                        _params.presentValueParams.initialSharePrice
                    ) + ONE
                )
                .pow(
                    // TODO: Account for rounding here.
                    _params.presentValueParams.timeStretch.divDown(
                        ONE - _params.presentValueParams.timeStretch
                    )
                )
        );
        derivative =
            derivative -
            _params.originalBondReserves.divDown(
                _originalEffectiveShareReserves
            );
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
        return derivative;
    }

    // FIXME: Todos
    //
    // 1. [ ] Document this body of this function.
    // 2. [ ] Check that we're rounding in the right direction.
    // 3. [ ] Double check this calculation.
    // 4. [ ] Add ASCII math.
    //
    /// @dev Calculates the derivative of `calculateMaxSellSharesOut`.
    /// @param _params The parameters for the calculation.
    /// @return The derivative.
    function calculateMaxSellSharesOutDerivative(
        DistributeExcessIdleParams memory _params
    ) internal pure returns (uint256) {
        if (_params.originalShareAdjustment >= 0) {
            return
                ONE -
                uint256(_params.originalShareAdjustment).divDown(
                    _params.originalShareReserves
                );
        } else {
            return
                ONE +
                uint256(-_params.originalShareAdjustment).divDown(
                    _params.originalShareReserves
                );
        }
    }
}
