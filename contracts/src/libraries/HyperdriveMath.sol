/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { FixedPointMath, ONE } from "./FixedPointMath.sol";
import { YieldSpaceMath } from "./YieldSpaceMath.sol";
import { SafeCast } from "./SafeCast.sol";

/// @author DELV
/// @title Hyperdrive
/// @notice Math for the Hyperdrive pricing model.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library HyperdriveMath {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;

    /// @dev Calculates the spot price without slippage of bonds in terms of base.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _initialSharePrice The initial share price as an 18 fixed-point value.
    /// @param _timeStretch The time stretch parameter as an 18 fixed-point value.
    /// @return spotPrice The spot price of bonds in terms of base as an 18 fixed-point value.
    function calculateSpotPrice(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _initialSharePrice,
        uint256 _timeStretch
    ) internal pure returns (uint256 spotPrice) {
        // (y / (mu * z)) ** -ts
        // ((mu * z) / y) ** ts
        spotPrice = _initialSharePrice
            .mulDivDown(_shareReserves, _bondReserves)
            .pow(_timeStretch);
    }

    /// @dev Calculates the APR from the pool's reserves.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _initialSharePrice The pool's initial share price.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @return apr The pool's APR.
    function calculateAPRFromReserves(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _initialSharePrice,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 apr) {
        // We are interested calculating the fixed APR for the pool. The rate is calculated by
        // dividing current spot price of the bonds by the position duration time, t.  To get the
        // annual rate, we scale t up to a year.
        uint256 annualizedTime = _positionDuration.divDown(365 days);

        uint256 spotPrice = calculateSpotPrice(
            _shareReserves,
            _bondReserves,
            _initialSharePrice,
            _timeStretch
        );

        // r = (1 - p) / (p * t)
        return (ONE - spotPrice).divDown(spotPrice.mulDown(annualizedTime));
    }

    /// @dev Calculates the initial bond reserves assuming that the initial LP
    ///      receives LP shares amounting to c * z + y. Throughout the rest of
    ///      the codebase, the bond reserves used include the LP share
    ///      adjustment specified in YieldSpace. The bond reserves returned by
    ///      this function are unadjusted which makes it easier to calculate the
    ///      initial LP shares.
    /// @param _shareReserves The pool's share reserves.
    /// @param _initialSharePrice The pool's initial share price.
    /// @param _apr The pool's APR.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @return bondReserves The bond reserves (without adjustment) that make
    ///         the pool have a specified APR.
    function calculateInitialBondReserves(
        uint256 _shareReserves,
        uint256 _initialSharePrice,
        uint256 _apr,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 bondReserves) {
        // NOTE: Using divDown to convert to fixed point format.
        uint256 t = _positionDuration.divDown(365 days);
        uint256 tau = ONE.mulDown(_timeStretch);
        // mu * z * (1 + apr * t) ** (1 / tau)
        return
            _initialSharePrice.mulDown(_shareReserves).mulDown(
                (ONE + _apr.mulDown(t)).pow(ONE.divUp(tau))
            );
    }

    /// @dev Calculates the number of bonds a user will receive when opening a long position.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _shareAmount The amount of shares the user is depositing.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return bondReservesDelta The bonds paid by the reserves in the trade.
    function calculateOpenLong(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _shareAmount,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    ) internal pure returns (uint256) {
        // (time remaining)/(term length) is always 1 so we just use _timeStretch
        return
            YieldSpaceMath.calculateBondsOutGivenSharesIn(
                _shareReserves,
                _bondReserves,
                _shareAmount,
                ONE - _timeStretch,
                _sharePrice,
                _initialSharePrice
            );
    }

    /// @dev Calculates the amount of shares a user will receive when closing a
    ///      long position.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _amountIn The amount of bonds the user is closing.
    /// @param _normalizedTimeRemaining The normalized time remaining of the
    ///        position.
    /// @param _timeStretch The time stretch parameter.
    /// @param _openSharePrice The share price at open.
    /// @param _closeSharePrice The share price at close.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The share price when the pool was deployed.
    /// @return shareReservesDelta The shares paid by the reserves in the trade.
    /// @return bondReservesDelta The bonds paid to the reserves in the trade.
    /// @return shareProceeds The shares that the user will receive.
    function calculateCloseLong(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _openSharePrice,
        uint256 _closeSharePrice,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    )
        internal
        pure
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 shareProceeds
        )
    {
        // We consider (1 - timeRemaining) * amountIn of the bonds to be fully
        // matured and timeRemaining * amountIn of the bonds to be newly
        // minted. The fully matured bonds are redeemed one-to-one to base
        // (our result is given in shares, so we divide the one-to-one
        // redemption by the share price) and the newly minted bonds are
        // traded on a YieldSpace curve configured to timeRemaining = 1.
        shareProceeds = _amountIn.mulDivDown(
            ONE - _normalizedTimeRemaining,
            _sharePrice
        );
        if (_normalizedTimeRemaining > 0) {
            // Calculate the curved part of the trade.
            bondReservesDelta = _amountIn.mulDown(_normalizedTimeRemaining);

            // (time remaining)/(term length) is always 1 so we just use _timeStretch
            shareReservesDelta = YieldSpaceMath.calculateSharesOutGivenBondsIn(
                _shareReserves,
                _bondReserves,
                bondReservesDelta,
                ONE - _timeStretch,
                _sharePrice,
                _initialSharePrice
            );
            shareProceeds += shareReservesDelta;
        }

        // If there's net negative interest over the period, the result of close long
        // is adjusted down by the rate of negative interest. We always attribute negative
        // interest to the long since it's difficult or impossible to attribute
        // the negative interest to the short in practice.
        if (_openSharePrice > _closeSharePrice) {
            shareProceeds = shareProceeds.mulDivDown(
                _closeSharePrice,
                _openSharePrice
            );
            shareReservesDelta = shareReservesDelta.mulDivDown(
                _closeSharePrice,
                _openSharePrice
            );
        }
    }

    /// @dev Calculates the amount of shares that will be received given a
    ///      specified amount of bonds.
    /// @param _shareReserves The pool's share reserves
    /// @param _bondReserves The pool's bonds reserves.
    /// @param _amountIn The amount of bonds the user is providing.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return The shares paid by the reserves in the trade.
    function calculateOpenShort(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    ) internal pure returns (uint256) {
        // (time remaining)/(term length) is always 1 so we just use _timeStretch
        return
            YieldSpaceMath.calculateSharesOutGivenBondsIn(
                _shareReserves,
                _bondReserves,
                _amountIn,
                ONE - _timeStretch,
                _sharePrice,
                _initialSharePrice
            );
    }

    /// @dev Calculates the amount of base that a user will receive when closing a short position
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bonds reserves.
    /// @param _amountOut The amount of the asset that is received.
    /// @param _normalizedTimeRemaining The amount of time remaining until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return shareReservesDelta The shares paid to the reserves in the trade.
    /// @return bondReservesDelta The bonds paid by the reserves in the trade.
    /// @return sharePayment The shares that the user must pay.
    function calculateCloseShort(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    )
        internal
        pure
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 sharePayment
        )
    {
        // Since we are buying bonds, it's possible that timeRemaining < 1.
        // We consider (1-timeRemaining)*amountOut of the bonds being
        // purchased to be fully matured and timeRemaining*amountOut of the
        // bonds to be newly minted. The fully matured bonds are redeemed
        // one-to-one to base (our result is given in shares, so we divide
        // the one-to-one redemption by the share price) and the newly
        // minted bonds are traded on a YieldSpace curve configured to
        // timeRemaining = 1.
        sharePayment = _amountOut.mulDivDown(
            ONE - _normalizedTimeRemaining,
            _sharePrice
        );
        bondReservesDelta = _amountOut.mulDown(_normalizedTimeRemaining);
        if (bondReservesDelta > 0) {
            shareReservesDelta = YieldSpaceMath.calculateSharesInGivenBondsOut(
                _shareReserves,
                _bondReserves,
                bondReservesDelta,
                ONE - _timeStretch,
                _sharePrice,
                _initialSharePrice
            );
            sharePayment += shareReservesDelta;
        }
    }

    struct MaxTradeParams {
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 longsOutstanding;
        uint256 longExposure;
        uint256 timeStretch;
        uint256 sharePrice;
        uint256 initialSharePrice;
        uint256 minimumShareReserves;
        uint256 curveFee;
        uint256 governanceFee;
    }

    // FIXME: I don't think that this correctly handles the case where the
    // checkpoint starts with negative exposure.
    //
    // FIXME: Instead of exposure increasing immediately, we should first eat
    // through the negative checkpoint exposure.
    //
    /// @dev Gets the max long that can be opened given a budget.
    ///
    ///      We start by calculating the long that brings the pool's spot price
    ///      to 1. If we are solvent at this point, then we're done. Otherwise,
    ///      we approach the max long iteratively using Newton's method.
    /// @param _params The parameters for the max long calculation.
    /// @param _maxIterations The maximum number of iterations to use in the
    ///                       Newton's method loop.
    /// @return maxBaseAmount The maximum base amount.
    /// @return maxBondAmount The maximum bond amount.
    function calculateMaxLong(
        MaxTradeParams memory _params,
        int256 _checkpointLongExposure,
        uint256 _maxIterations
    ) internal pure returns (uint256 maxBaseAmount, uint256 maxBondAmount) {
        // Get the maximum long that brings the spot price to 1. If the pool is
        // solvent after opening this long, then we're done.
        uint256 spotPrice = calculateSpotPrice(
            _params.shareReserves,
            _params.bondReserves,
            _params.initialSharePrice,
            _params.timeStretch
        );
        uint256 absoluteMaxBaseAmount;
        uint256 absoluteMaxBondAmount;
        {
            uint256 maxShareAmount;
            (maxShareAmount, absoluteMaxBondAmount) = YieldSpaceMath
                .calculateMaxBuy(
                    _params.shareReserves,
                    _params.bondReserves,
                    ONE - _params.timeStretch,
                    _params.sharePrice,
                    _params.initialSharePrice
                );
            absoluteMaxBaseAmount = maxShareAmount.mulDown(_params.sharePrice);
            (, bool isSolvent_) = calculateSolvency(
                _params,
                _checkpointLongExposure,
                absoluteMaxBaseAmount,
                absoluteMaxBondAmount,
                spotPrice
            );
            if (isSolvent_) {
                return (absoluteMaxBaseAmount, absoluteMaxBondAmount);
            }
        }

        // Use Newton's method to iteratively approach a solution. We use pool's
        // solvency $S(x)$ as our objective function, which will converge to the
        // amount of base that needs to be paid to open the maximum long. The
        // derivative of $S(x)$ is negative (since solvency decreases as more
        // longs are opened). The fixed point library doesn't support negative
        // numbers, so we use the negation of the derivative to side-step the
        // issue.
        //
        // Given the current guess of $x_n$, Newton's method gives us an updated
        // guess of $x_{n+1}$:
        //
        // $$
        // x_{n+1} = x_n - \tfrac{S(x_n)}{S'(x_n)} = x_n + \tfrac{S(x_n)}{-S'(x_n)}
        // $$
        //
        // The guess that we make is very important in determining how quickly
        // we converge to the solution.
        maxBaseAmount = calculateMaxLongGuess(
            _params,
            _checkpointLongExposure,
            spotPrice
        );
        maxBondAmount = calculateLongAmount(_params, maxBaseAmount, spotPrice);
        (uint256 s, bool isSolvent) = calculateSolvency(
            _params,
            _checkpointLongExposure,
            maxBaseAmount,
            maxBondAmount,
            spotPrice
        );
        require(isSolvent, "Initial guess in `calculateMaxLong` is insolvent.");
        for (uint256 i = 0; i < _maxIterations; i++) {
            // If the base amount is greater than the absolute max base amount
            // (based on the spot price), we short circuit and return the
            // absolute maximum base and bond amounts.
            if (maxBaseAmount >= absoluteMaxBaseAmount) {
                return (absoluteMaxBaseAmount, absoluteMaxBondAmount);
            }

            // If the pool is solvent after the current guess, we proceed with
            // Newton's method. As Newton's method approaches the root, it can
            // cross over to the other side of the root. We truncuate Newton's
            // method when this happens.
            //
            // TODO: It may be better to gracefully handle crossing over the
            // root by extending the fixed point math library to handle negative
            // numbers or even just using an if-statement to handle the negative
            // numbers.
            if (isSolvent) {
                // Calculate the derivative of the objective function for
                // Newton's method. This should only fail near the root.
                (
                    uint256 derivative,
                    bool success
                ) = calculateSolvencyDerivative(
                        _params,
                        maxBaseAmount,
                        spotPrice
                    );
                if (!success) {
                    break;
                }

                // Calculate the next step of Newton's method and calculate the
                // ending solvency.
                maxBaseAmount += s.divDown(derivative);
                maxBondAmount = calculateLongAmount(
                    _params,
                    maxBaseAmount,
                    spotPrice
                );
                (s, isSolvent) = calculateSolvency(
                    _params,
                    _checkpointLongExposure,
                    maxBaseAmount,
                    maxBondAmount,
                    spotPrice
                );
            } else {
                break;
            }
        }

        return (maxBaseAmount, maxBondAmount);
    }

    /// @dev Gets a starting guess for the iterative process of finding the max
    ///      long.
    ///
    ///      To calculate our guess, we assume an unrealistically good realized
    ///      price $p_r$ for closing the long. This allows us to approximate
    ///      $y(x)$ as $y(x) \approx p_r^{-1} \cdot x - c(x)$. Plugging this
    ///      into our solvency function $s(x)$, we can calculate the share
    ///      reserves and exposure after opening a long with $x$ base as:
    ///
    ///      \begin{aligned}
    ///      z(x) &= z_0 + \tfrac{x - g(x)}{c} - z_{min} \\
    ///      e(x) &= e_0 + min(exposure_{c}, 0) + 2 \cdot y(x) - x + g(x) \\
    ///           &= e_0 + min(exposure_{c}, 0) + 2 \cdot p_r^{-1} \cdot x -
    ///                  2 \cdot c(x) - x + g(x)
    ///      \end{aligned}
    ///
    ///      We debit and negative checkpoint exposure from $e_0$ since the
    ///      global exposure doesn't take into account the negative exposure
    ///      from unnetted shorts in the checkpoint. These forumulas allow us
    ///      to calculate the approximate ending solvency of:
    ///
    ///      $$
    ///      s(x) \approx z(x) - \tfrac{e(x)}{c} - z_{min}
    ///      $$
    ///
    ///      If we let the initial solvency be given by $s_0$, we can solve for
    ///      $x$ as:
    ///
    ///      $$
    ///      x = \frac{c}{2} \cdot \frac{s_0 + min(exposure_{c}, 0)}{
    ///              p_r^{-1} +
    ///              \phi_{g} \cdot \phi_{c} \cdot \left( 1 - p \right) -
    ///              1 -
    ///              \phi_{c} \cdot \left( p^{-1} - 1 \right)
    ///          }
    ///      $$
    ///
    ///      We need to use a conservative estimate for the realized price, so
    ///      we use the spot price $p$ as our estimate price.
    /// @param _params The max long calculation parameters.
    /// @param _spotPrice The spot price of the pool.
    /// @return The starting guess for the iterative process of finding the max
    ///         long.
    function calculateMaxLongGuess(
        MaxTradeParams memory _params,
        int256 _checkpointLongExposure,
        uint256 _spotPrice
    ) internal pure returns (uint256) {
        uint256 estimatePrice = _spotPrice;
        uint256 checkpointExposure = uint256(-_checkpointLongExposure.min(0));
        uint256 guess = (_params.shareReserves +
            checkpointExposure.divDown(_params.sharePrice) -
            _params.longExposure.divDown(_params.sharePrice) -
            _params.minimumShareReserves).mulDivDown(_params.sharePrice, 2e18);
        guess = guess.divDown(
            ONE.divDown(estimatePrice) +
                _params.governanceFee.mulDown(_params.curveFee).mulDown(
                    ONE - _spotPrice
                ) -
                ONE -
                _params.curveFee.mulDown(ONE.divDown(_spotPrice) - ONE)
        );
        return guess;
    }

    /// @dev Gets the solvency of the pool $S(x)$ after a long is opened with a
    ///      base amount $x$.
    ///
    ///      Since longs can net out with shorts in this checkpoint, we decrease
    ///      the global exposure variable by any negative long exposure we have
    ///      in the checkpoint. The pool's solvency is calculated as:
    ///
    ///      $$
    ///      s = z - \tfrac{exposure + min(exposure_{c}, 0)}{c} - z_{min}
    ///      $$
    ///
    ///      When a long is opened, the share reserves $z$ increase by:
    ///
    ///      $$
    ///      \Delta z = \tfrac{x - g(x)}{c}
    ///      $$
    ///
    ///      In the solidity implementation, we calculate the delta in the
    ///      exposure as:
    ///
    ///      ```
    ///      shareReservesDelta = _shareAmount - governanceCurveFee.divDown(_sharePrice)
    ///      uint128 longExposureDelta = (2 *
    ///          _bondProceeds -
    ///          _shareReservesDelta.mulDown(_sharePrice)).toUint128();
    ///      ```
    ///
    ///      From this, we can calculate our exposure as:
    ///
    ///      $$
    ///      \Delta exposure = 2 \cdot y(x) - x + g(x)
    ///      $$
    ///
    ///      From this, we can calculate $S(x)$ as:
    ///
    ///      $$
    ///      S(x) = \left( z + \Delta z \right) - \left(
    ///                 \tfrac{exposure + min(exposure_{c}, 0) + \Delta exposure}{c}
    ///             \right) - z_{min}
    ///      $$
    ///
    ///      It's possible that the pool is insolvent after opening a long. In
    ///      this case, we return `false` since the fixed point library can't
    ///      represent negative numbers.
    /// @param _params The max long calculation parameters.
    /// @param _baseAmount The base amount.
    /// @param _bondAmount The bond amount.
    /// @param _spotPrice The spot price.
    /// @return The solvency of the pool.
    /// @return A flag indicating that the pool is solvent if true and insolvent
    ///         if false.
    function calculateSolvency(
        MaxTradeParams memory _params,
        int256 _checkpointLongExposure,
        uint256 _baseAmount,
        uint256 _bondAmount,
        uint256 _spotPrice
    ) internal pure returns (uint256, bool) {
        uint256 governanceFee = calculateLongGovernanceFee(
            _baseAmount,
            _spotPrice,
            _params.curveFee,
            _params.governanceFee
        );
        uint256 shareReserves = _params.shareReserves +
            _baseAmount.divDown(_params.sharePrice) -
            governanceFee.divDown(_params.sharePrice);
        uint256 exposure = _params.longExposure +
            2 *
            _bondAmount -
            _baseAmount +
            governanceFee;
        uint256 checkpointExposure = uint256(-_checkpointLongExposure.min(0));
        if (
            shareReserves + checkpointExposure.divDown(_params.sharePrice) >=
            exposure.divDown(_params.sharePrice) + _params.minimumShareReserves
        ) {
            return (
                shareReserves +
                    checkpointExposure.divDown(_params.sharePrice) -
                    exposure.divDown(_params.sharePrice) -
                    _params.minimumShareReserves,
                true
            );
        } else {
            return (0, false);
        }
    }

    /// @dev Gets the negation of the derivative of the pool's solvency with
    ///      respect to the base amount that the long pays.
    ///
    ///      The derivative of the pool's solvency $S(x)$ with respect to the
    ///      base amount that the long pays is given by:
    ///
    ///      $$
    ///      S'(x) = \tfrac{2}{c} \cdot \left(
    ///                  1 - y'(x) - \phi_{g} \cdot p \cdot c'(x)
    ///              \right) \\
    ///            = \tfrac{2}{c} \cdot \left(
    ///                  1 - y'(x) - \phi_{g} \cdot \phi_{c} \cdot \left( 1 - p \right)
    ///              \right)
    ///      $$
    ///
    ///      This derivative is negative since solvency decreases as more longs
    ///      are opened. We use the negation of the derivative to stay in the
    ///      positive domain, which allows us to use the fixed point library.
    /// @param _params The max long calculation parameters.
    /// @param _baseAmount The base amount.
    /// @param _spotPrice The spot price.
    /// @return derivative The negation of the derivative of the pool's solvency
    ///         w.r.t the base amount.
    /// @return success A flag indicating whether or not the derivative was
    ///         successfully calculated.
    function calculateSolvencyDerivative(
        MaxTradeParams memory _params,
        uint256 _baseAmount,
        uint256 _spotPrice
    ) internal pure returns (uint256 derivative, bool success) {
        // Calculate the derivative of the long amount. This calculation can
        // fail when we are close to the root. In these cases, we exit early.
        (derivative, success) = calculateLongAmountDerivative(
            _params,
            _baseAmount,
            _spotPrice
        );
        if (!success) {
            return (0, success);
        }

        // Finish computing the derivative.
        derivative += _params.governanceFee.mulDown(_params.curveFee).mulDown(
            ONE - _spotPrice
        );
        derivative -= ONE;

        return (derivative.mulDivDown(2e18, _params.sharePrice), success);
    }

    /// @dev Gets the long amount that will be opened for a given base amount.
    ///
    ///      The long amount $y(x)$ that a trader will receive is given by:
    ///
    ///      $$
    ///      y(x) = y_{*}(x) - c(x)
    ///      $$
    ///
    ///      Where $y_{*}(x)$ is the amount of long that would be opened if there
    ///      was no curve fee and [$c(x)$](long_curve_fee) is the curve fee.
    ///      $y_{*}(x)$ is given by:
    ///
    ///      $$
    ///      y_{*}(x) = y - \left(
    ///                     k - \tfrac{c}{\mu} \cdot \left(
    ///                         \mu \cdot \left( z + \tfrac{x}{c}
    ///                     \right) \right)^{1 - t_s}
    ///                 \right)^{\tfrac{1}{1 - t_s}}
    ///      $$
    /// @param _params The max long calculation parameters.
    /// @param _baseAmount The base amount.
    /// @param _spotPrice The spot price.
    /// @return The long amount.
    function calculateLongAmount(
        MaxTradeParams memory _params,
        uint256 _baseAmount,
        uint256 _spotPrice
    ) internal pure returns (uint256) {
        uint256 longAmount = YieldSpaceMath.calculateBondsOutGivenSharesIn(
            _params.shareReserves,
            _params.bondReserves,
            _baseAmount.divDown(_params.sharePrice),
            ONE - _params.timeStretch,
            _params.sharePrice,
            _params.initialSharePrice
        );
        return
            longAmount -
            calculateLongCurveFee(_baseAmount, _spotPrice, _params.curveFee);
    }

    /// @dev Gets the derivative of [long_amount](long_amount) with respect to
    ///      the base amount.
    ///
    ///      We calculate the derivative of the long amount $y(x)$ as:
    ///
    ///      $$
    ///      y'(x) = y_{*}'(x) - c'(x)
    ///      $$
    ///
    ///      Where $y_{*}'(x)$ is the derivative of $y_{*}(x)$ and $c'(x)$ is the
    ///      derivative of [$c(x)$](long_curve_fee). $y_{*}'(x)$ is given by:
    ///
    ///      $$
    ///      y_{*}'(x) = \left( \mu \cdot (z + \tfrac{x}{c}) \right)^{-t_s}
    ///                  \left(
    ///                      k - \tfrac{c}{\mu} \cdot
    ///                      \left(
    ///                          \mu \cdot (z + \tfrac{x}{c}
    ///                      \right)^{1 - t_s}
    ///                  \right)^{\tfrac{t_s}{1 - t_s}}
    ///      $$
    ///
    ///      and $c'(x)$ is given by:
    ///
    ///      $$
    ///      c'(x) = \phi_{c} \cdot \left( \tfrac{1}{p} - 1 \right)
    ///      $$
    /// @param _params The max long calculation parameters.
    /// @param _baseAmount The base amount.
    /// @param _spotPrice The spot price.
    /// @return derivative The derivative of the long amount w.r.t. the base
    ///         amount.
    /// @return A flag indicating whether or not the derivative was
    ///         successfully calculated.
    function calculateLongAmountDerivative(
        MaxTradeParams memory _params,
        uint256 _baseAmount,
        uint256 _spotPrice
    ) internal pure returns (uint256 derivative, bool) {
        // Compute the first part of the derivative.
        uint256 shareAmount = _baseAmount.divDown(_params.sharePrice);
        uint256 inner = _params.initialSharePrice.mulDown(
            _params.shareReserves + shareAmount
        );
        uint256 cDivMu = _params.sharePrice.divDown(_params.initialSharePrice);
        uint256 k = YieldSpaceMath.modifiedYieldSpaceConstant(
            cDivMu,
            _params.initialSharePrice,
            _params.shareReserves,
            ONE - _params.timeStretch,
            _params.bondReserves
        );
        derivative = ONE.divDown(inner.pow(_params.timeStretch));

        // It's possible that k is slightly larger than the rhs in the inner
        // calculation. If this happens, we are close to the root, and we short
        // circuit.
        uint256 rhs = cDivMu.mulDown(inner.pow(_params.timeStretch));
        if (k < rhs) {
            return (0, false);
        }
        derivative = derivative.mulDown(
            (k - rhs).pow(_params.timeStretch.divUp(ONE - _params.timeStretch))
        );

        // Finish computing the derivative.
        derivative -= _params.curveFee.mulDown(ONE.divDown(_spotPrice) - ONE);

        return (derivative, true);
    }

    /// @dev Gets the curve fee paid by longs for a given base amount.
    ///
    ///      The curve fee $c(x)$ paid by longs is given by:
    ///
    ///      $$
    ///      c(x) = \phi_{c} \cdot \left( \tfrac{1}{p} - 1 \right) \cdot x
    ///      $$
    /// @param _baseAmount The base amount, $x$.
    /// @param _spotPrice The spot price, $p$.
    /// @param _curveFee The curve fee, $\phi_{c}$.
    function calculateLongCurveFee(
        uint256 _baseAmount,
        uint256 _spotPrice,
        uint256 _curveFee
    ) internal pure returns (uint256) {
        // fee = curveFee * (1/p - 1) * x
        return
            _curveFee.mulDown(ONE.divDown(_spotPrice) - ONE).mulDown(
                _baseAmount
            );
    }

    /// @dev Gets the governance fee paid by longs for a given base amount.
    ///
    ///      Unlike the [curve fee](long_curve_fee) which is paid in bonds, the
    ///      governance fee is paid in base. The governance fee $g(x)$ paid by
    ///      longs is given by:
    ///
    ///      $$
    ///      g(x) = \phi_{g} \cdot p \cdot c(x)
    ///      $$
    /// @param _baseAmount The base amount, $x$.
    /// @param _spotPrice The spot price, $p$.
    /// @param _curveFee The curve fee, $\phi_{c}$.
    /// @param _governanceFee The governance fee, $\phi_{g}$.
    function calculateLongGovernanceFee(
        uint256 _baseAmount,
        uint256 _spotPrice,
        uint256 _curveFee,
        uint256 _governanceFee
    ) internal pure returns (uint256) {
        return
            _governanceFee.mulDown(_spotPrice).mulDown(
                calculateLongCurveFee(_baseAmount, _spotPrice, _curveFee)
            );
    }

    // TODO: This is an overly restrictive max short calculation. We can do
    // better if we iteratively approximate using solvency as an objective
    // function.
    //
    /// @dev Calculates the maximum amount of shares that can be used to open
    ///      shorts.
    /// @param _params Information about the market state and pool configuration
    ///        used to compute the maximum trade.
    /// @return The maximum amount of shares that can be used to open shorts.
    function calculateMaxShort(
        MaxTradeParams memory _params
    ) internal pure returns (uint256) {
        // The only constraint on the maximum short is that the share reserves
        // don't go negative and satisfy the solvency requirements. Thus, we can
        // set z = z_min and solve for the maximum short directly as:
        //
        // k = (c / mu) * (mu * (y_l/c + z_min)) ** (1 - tau) + y ** (1 - tau)
        //                         =>
        // y = (k - (c / mu) * (mu * (y_l/c + z_min)) ** (1 - tau)) ** (1 / (1 - tau)).
        uint256 t = ONE - _params.timeStretch;
        uint256 priceFactor = _params.sharePrice.divDown(
            _params.initialSharePrice
        );
        uint256 k = YieldSpaceMath.modifiedYieldSpaceConstant(
            priceFactor,
            _params.initialSharePrice,
            _params.shareReserves,
            t,
            _params.bondReserves
        );
        uint256 innerFactor = _params
            .initialSharePrice
            .mulDown(
                _params.longsOutstanding.divDown(_params.sharePrice) +
                    _params.minimumShareReserves
            )
            .pow(t);
        uint256 optimalBondReserves = (k - priceFactor.mulDown(innerFactor))
            .pow(ONE.divDown(t));

        // The optimal bond reserves imply a maximum short of dy = y - y0.
        return optimalBondReserves - _params.bondReserves;
    }

    struct PresentValueParams {
        uint256 shareReserves;
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
        // Compute the net of the longs and shorts that will be traded on the
        // curve and apply this net to the reserves.
        int256 netCurveTrade = int256(
            _params.longsOutstanding.mulDown(_params.longAverageTimeRemaining)
        ) -
            int256(
                _params.shortsOutstanding.mulDown(
                    _params.shortAverageTimeRemaining
                )
            );
        if (netCurveTrade > 0) {
            // Close as many longs as possible on the curve. Any longs that
            // can't be closed will be stuck until maturity (assuming nothing
            // changes) at which time the longs will receive the bond's face
            // value and the LPs will receive any variable interest that is
            // collected. It turns out that the value that we place on these
            // stuck longs doesn't have an impact on LP fairness since longs
            // are only stuck when there is no idle remaining. With this in
            // mind, we mark the longs to zero for simplicity and to avoid
            // unnecessary computation.
            (, uint256 maxCurveTrade) = YieldSpaceMath.calculateMaxSell(
                _params.shareReserves,
                _params.bondReserves,
                _params.minimumShareReserves,
                ONE - _params.timeStretch,
                _params.sharePrice,
                _params.initialSharePrice
            );
            maxCurveTrade = maxCurveTrade.min(uint256(netCurveTrade)); // netCurveTrade is non-negative, so this is safe.
            if (maxCurveTrade > 0) {
                _params.shareReserves -= YieldSpaceMath
                    .calculateSharesOutGivenBondsIn(
                        _params.shareReserves,
                        _params.bondReserves,
                        uint256(netCurveTrade),
                        ONE - _params.timeStretch,
                        _params.sharePrice,
                        _params.initialSharePrice
                    );
            }
        } else if (netCurveTrade < 0) {
            // Close as many shorts as possible on the curve. Any shorts that
            // can't be closed will be stuck until maturity (assuming nothing
            // changes) at which time the LPs will receive the bond's face
            // value. If we value the stuck shorts at less than the face value,
            // LPs that remove liquidity before liquidity will receive a smaller
            // amount of withdrawal shares than they should. On the other hand,
            // if we value the stuck shorts at more than the face value, LPs
            // that remove liquidity before maturity will receive a larger
            // amount of withdrawal shares than they should. With this in mind,
            // we value the stuck shorts at exactly the face value.
            netCurveTrade = -netCurveTrade; // Switch to a positive value for convenience.
            (, uint256 maxCurveTrade) = YieldSpaceMath.calculateMaxBuy(
                _params.shareReserves,
                _params.bondReserves,
                ONE - _params.timeStretch,
                _params.sharePrice,
                _params.initialSharePrice
            );
            maxCurveTrade = maxCurveTrade.min(uint256(netCurveTrade)); // netCurveTrade is positive, so this is safe.
            if (maxCurveTrade > 0) {
                _params.shareReserves += YieldSpaceMath
                    .calculateSharesInGivenBondsOut(
                        _params.shareReserves,
                        _params.bondReserves,
                        maxCurveTrade,
                        ONE - _params.timeStretch,
                        _params.sharePrice,
                        _params.initialSharePrice
                    );
            }
            _params.shareReserves += uint256(netCurveTrade) - maxCurveTrade;
        }

        // Compute the net of the longs and shorts that will be traded flat
        // and apply this net to the reserves.
        int256 netFlatTrade = int256(
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
        _params.shareReserves = uint256(
            int256(_params.shareReserves) + netFlatTrade
        );

        // The present value is the final share reserves minus the minimum share
        // reserves. This ensures that LP withdrawals won't include the minimum
        // share reserves.
        return _params.shareReserves - _params.minimumShareReserves;
    }

    /// @dev Calculates the proceeds in shares of closing a short position. This
    ///      takes into account the trading profits, the interest that was
    ///      earned by the short, and the amount of margin that was released
    ///      by closing the short. The math for the short's proceeds in base is
    ///      given by:
    ///
    ///      proceeds = dy - c * dz + (c1 - c0) * (dy / c0)
    ///               = dy - c * dz + (c1 / c0) * dy - dy
    ///               = (c1 / c0) * dy - c * dz
    ///
    ///      We convert the proceeds to shares by dividing by the current share
    ///      price. In the event that the interest is negative and outweighs the
    ///      trading profits and margin released, the short's proceeds are
    ///      marked to zero.
    /// @param _bondAmount The amount of bonds underlying the closed short.
    /// @param _shareAmount The amount of shares that it costs to close the
    ///                     short.
    /// @param _openSharePrice The share price at the short's open.
    /// @param _closeSharePrice The share price at the short's close.
    /// @param _sharePrice The current share price.
    /// @param _flatFee The flat fee currently within the pool
    /// @return shareProceeds The short proceeds in shares.
    function calculateShortProceeds(
        uint256 _bondAmount,
        uint256 _shareAmount,
        uint256 _openSharePrice,
        uint256 _closeSharePrice,
        uint256 _sharePrice,
        uint256 _flatFee
    ) internal pure returns (uint256 shareProceeds) {
        // If the interest is more negative than the trading profits and margin
        // released, than the short proceeds are marked to zero. Otherwise, we
        // calculate the proceeds as the sum of the trading proceeds, the
        // interest proceeds, and the margin released.
        uint256 bondFactor = _bondAmount.mulDivDown(
            _closeSharePrice,
            // We round up here do avoid overestimating the share proceeds.
            _openSharePrice.mulUp(_sharePrice)
        );

        // We increase the bondFactor by the flat fee amount, because the trader
        // has provided the flat fee as margin, and so it must be returned to
        // them if it's not charged.
        bondFactor += _bondAmount.mulDivDown(_flatFee, _sharePrice);

        if (bondFactor > _shareAmount) {
            // proceeds = (c1 / c0 * c) * dy - dz
            shareProceeds = bondFactor - _shareAmount;
        }
        return shareProceeds;
    }

    /// @dev Calculates the interest in shares earned by a short position. The
    ///      math for the short's interest in shares is given by:
    ///
    ///      interest = ((c1 / c0 - 1) * dy) / c
    ///               = (((c1 - c0) / c0) * dy) / c
    ///               = ((c1 - c0) / (c0 * c)) * dy
    ///
    ///      In the event that the interest is negative, we mark the interest
    ///      to zero.
    /// @param _bondAmount The amount of bonds underlying the closed short.
    /// @param _openSharePrice The share price at the short's open.
    /// @param _closeSharePrice The share price at the short's close.
    /// @param _sharePrice The current share price.
    /// @return shareInterest The short interest in shares.
    function calculateShortInterest(
        uint256 _bondAmount,
        uint256 _openSharePrice,
        uint256 _closeSharePrice,
        uint256 _sharePrice
    ) internal pure returns (uint256 shareInterest) {
        // If the interest is negative, we mark it to zero.
        if (_closeSharePrice > _openSharePrice) {
            // interest = dy * ((c1 - c0) / (c0 * c))
            shareInterest = _bondAmount.mulDivDown(
                _closeSharePrice - _openSharePrice,
                // We round up here do avoid overestimating the share interest.
                _openSharePrice.mulUp(_sharePrice)
            );
        }
    }
}
