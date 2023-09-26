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

    /// @dev Calculates the spot price of bonds in terms of base.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _initialSharePrice The initial share price.
    /// @param _timeStretch The time stretch parameter.
    /// @return spotPrice The spot price of bonds in terms of base.
    function calculateSpotPrice(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _initialSharePrice,
        uint256 _timeStretch
    ) internal pure returns (uint256 spotPrice) {
        // p = (y / (mu * (z - zeta))) ** -t_s
        //   = ((mu * (z - zeta)) / y) ** t_s
        spotPrice = _initialSharePrice
            .mulDivDown(_effectiveShareReserves, _bondReserves)
            .pow(_timeStretch);
    }

    // FIXME: Rename this to calculateSpotRate.
    //
    /// @dev Calculates the APR from the pool's reserves.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _initialSharePrice The pool's initial share price.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @return apr The pool's APR.
    function calculateAPRFromReserves(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _initialSharePrice,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 apr) {
        // We are interested calculating the fixed APR for the pool. The annualized rate
        // is given by the following formula:
        // r = (1 - p) / (p * t)
        // where t = 365 / _positionDuration

        uint256 spotPrice = calculateSpotPrice(
            _effectiveShareReserves,
            _bondReserves,
            _initialSharePrice,
            _timeStretch
        );
        return
            (ONE - spotPrice).divDown(
                spotPrice.mulDivUp(365 days, _positionDuration)
            );
    }

    /// @dev Calculates the initial bond reserves assuming that the initial LP
    ///      receives LP shares amounting to c * z + y. Throughout the rest of
    ///      the codebase, the bond reserves used include the LP share
    ///      adjustment specified in YieldSpace. The bond reserves returned by
    ///      this function are unadjusted which makes it easier to calculate the
    ///      initial LP shares.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _initialSharePrice The pool's initial share price.
    /// @param _apr The pool's APR.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @return bondReserves The bond reserves (without adjustment) that make
    ///         the pool have a specified APR.
    function calculateInitialBondReserves(
        uint256 _effectiveShareReserves,
        uint256 _initialSharePrice,
        uint256 _apr,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 bondReserves) {
        // NOTE: Using divDown to convert to fixed point format.
        uint256 t = _positionDuration.divDown(365 days);

        // mu * (z - zeta) * (1 + apr * t) ** (1 / tau)
        return
            _initialSharePrice.mulDown(_effectiveShareReserves).mulDown(
                (ONE + _apr.mulDown(t)).pow(ONE.divUp(_timeStretch))
            );
    }

    /// @dev Calculates the number of bonds a user will receive when opening a
    ///      long position.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _shareAmount The amount of shares the user is depositing.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return bondReservesDelta The bonds paid by the reserves in the trade.
    function calculateOpenLong(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _shareAmount,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    ) internal pure returns (uint256) {
        // (time remaining)/(term length) is always 1 so we just use _timeStretch
        return
            YieldSpaceMath.calculateBondsOutGivenSharesIn(
                _effectiveShareReserves,
                _bondReserves,
                _shareAmount,
                ONE - _timeStretch,
                _sharePrice,
                _initialSharePrice
            );
    }

    /// @dev Calculates the amount of shares a user will receive when closing a
    ///      long position.
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
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
        uint256 _effectiveShareReserves,
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
                _effectiveShareReserves,
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
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
    /// @param _bondReserves The pool's bonds reserves.
    /// @param _amountIn The amount of bonds the user is providing.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return The shares paid by the reserves in the trade.
    function calculateOpenShort(
        uint256 _effectiveShareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _timeStretch,
        uint256 _sharePrice,
        uint256 _initialSharePrice
    ) internal pure returns (uint256) {
        // (time remaining)/(term length) is always 1 so we just use _timeStretch
        return
            YieldSpaceMath.calculateSharesOutGivenBondsIn(
                _effectiveShareReserves,
                _bondReserves,
                _amountIn,
                ONE - _timeStretch,
                _sharePrice,
                _initialSharePrice
            );
    }

    /// @dev Calculates the amount of base that a user will receive when closing a short position
    /// @param _effectiveShareReserves The pool's effective share reserves. The
    ///        effective share reserves are a modified version of the share
    ///        reserves used when pricing trades.
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
        uint256 _effectiveShareReserves,
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
                _effectiveShareReserves,
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
        int256 shareAdjustment;
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

    /// @dev Gets the max long that can be opened given a budget.
    ///
    ///      We start by calculating the long that brings the pool's spot price
    ///      to 1. If we are solvent at this point, then we're done. Otherwise,
    ///      we approach the max long iteratively using Newton's method.
    /// @param _params The parameters for the max long calculation.
    /// @param _checkpointLongExposure The long exposure in the checkpoint.
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
        uint256 effectiveShareReserves = calculateEffectiveShareReserves(
            _params.shareReserves,
            _params.shareAdjustment
        );
        uint256 spotPrice = calculateSpotPrice(
            effectiveShareReserves,
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
                    effectiveShareReserves,
                    _params.bondReserves,
                    ONE - _params.timeStretch,
                    _params.sharePrice,
                    _params.initialSharePrice
                );
            absoluteMaxBaseAmount = maxShareAmount.mulDown(_params.sharePrice);
            absoluteMaxBondAmount -= calculateLongCurveFee(
                absoluteMaxBaseAmount,
                spotPrice,
                _params.curveFee
            );
            (, bool isSolvent_) = calculateSolvencyAfterLong(
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
            absoluteMaxBaseAmount,
            _checkpointLongExposure,
            spotPrice
        );
        maxBondAmount = calculateLongAmount(
            _params,
            maxBaseAmount,
            effectiveShareReserves,
            spotPrice
        );
        (uint256 solvency, bool success) = calculateSolvencyAfterLong(
            _params,
            _checkpointLongExposure,
            maxBaseAmount,
            maxBondAmount,
            spotPrice
        );
        require(success, "Initial guess in `calculateMaxLong` is insolvent.");
        for (uint256 i = 0; i < _maxIterations; i++) {
            // If the max base amount is equal to or exceeds the absolute max,
            // we've gone too far and the calculation deviated from reality at
            // some point.
            require(
                maxBaseAmount < absoluteMaxBaseAmount,
                "Reached absolute max bond amount in `get_max_long`."
            );

            // TODO: It may be better to gracefully handle crossing over the
            // root by extending the fixed point math library to handle negative
            // numbers or even just using an if-statement to handle the negative
            // numbers.
            //
            // Proceed to the next step of Newton's method. Once we have a
            // candidate solution, we check to see if the pool is solvent if
            // a long is opened with the candidate amount. If the pool isn't
            // solvent, then we're done.
            uint256 derivative;
            (derivative, success) = calculateSolvencyAfterLongDerivative(
                _params,
                maxBaseAmount,
                effectiveShareReserves,
                spotPrice
            );
            if (!success) {
                break;
            }
            uint256 possibleMaxBaseAmount = maxBaseAmount +
                solvency.divDown(derivative);
            uint256 possibleMaxBondAmount = calculateLongAmount(
                _params,
                possibleMaxBaseAmount,
                effectiveShareReserves,
                spotPrice
            );
            (solvency, success) = calculateSolvencyAfterLong(
                _params,
                _checkpointLongExposure,
                possibleMaxBaseAmount,
                possibleMaxBondAmount,
                spotPrice
            );
            if (success) {
                maxBaseAmount = possibleMaxBaseAmount;
                maxBondAmount = possibleMaxBondAmount;
            } else {
                break;
            }
        }

        return (maxBaseAmount, maxBondAmount);
    }

    /// @dev Calculates an initial guess of the max long that can be opened.
    ///      This is a reasonable estimate that is guaranteed to be less than
    ///      the true max long. We use this to get a reasonable starting point
    ///      for Newton's method.
    /// @param _params The max long calculation parameters.
    /// @param _absoluteMaxBaseAmount The absolute max base amount that can be
    ///        used to open a long.
    /// @param _checkpointLongExposure The long exposure in the checkpoint.
    /// @param _spotPrice The spot price of the pool.
    /// @return A conservative estimate of the max long that the pool can open.
    function calculateMaxLongGuess(
        MaxTradeParams memory _params,
        uint256 _absoluteMaxBaseAmount,
        int256 _checkpointLongExposure,
        uint256 _spotPrice
    ) internal pure returns (uint256) {
        // Get an initial estimate of the max long by using the spot price as
        // our conservative price.
        uint256 guess = calculateMaxLongEstimate(
            _params,
            _checkpointLongExposure,
            _spotPrice,
            _spotPrice
        );

        // We know that the spot price is 1 when the absolute max base amount is
        // used to open a long. We also know that our spot price isn't a great
        // estimate (conservative or otherwise) of the realized price that the
        // max long will pay, so we calculate a better estimate of the realized
        // price by interpolating between the spot price and 1 depending on how
        // large the estimate is.
        uint256 t = guess
            .divDown(_absoluteMaxBaseAmount)
            .pow(ONE.divUp(ONE - _params.timeStretch))
            .mulDown(0.8e18);
        uint256 estimateSpotPrice = _spotPrice.mulDown(ONE - t) +
            ONE.mulDown(t);

        // Recalculate our intial guess using the bootstrapped conservative
        // estimate of the realized price.
        guess = calculateMaxLongEstimate(
            _params,
            _checkpointLongExposure,
            _spotPrice,
            estimateSpotPrice
        );

        return guess;
    }

    /// @dev Estimates the max long based on the pool's current solvency and a
    ///      conservative price estimate, $p_r$.
    ///
    ///      We can use our estimate price $p_r$ to approximate $y(x)$ as
    ///      $y(x) \approx p_r^{-1} \cdot x - c(x)$. Plugging this into our
    ///      solvency function $s(x)$, we can calculate the share reserves and
    ///      exposure after opening a long with $x$ base as:
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
    /// @param _params The max long calculation parameters.
    /// @param _checkpointLongExposure The long exposure in the checkpoint.
    /// @param _spotPrice The spot price of the pool.
    /// @param _estimatePrice The estimated realized price the max long will pay.
    /// @return A conservative estimate of the max long that the pool can open.
    function calculateMaxLongEstimate(
        MaxTradeParams memory _params,
        int256 _checkpointLongExposure,
        uint256 _spotPrice,
        uint256 _estimatePrice
    ) internal pure returns (uint256) {
        uint256 checkpointExposure = uint256(-_checkpointLongExposure.min(0));
        uint256 estimate = (_params.shareReserves +
            checkpointExposure.divDown(_params.sharePrice) -
            _params.longExposure.divDown(_params.sharePrice) -
            _params.minimumShareReserves).mulDivDown(_params.sharePrice, 2e18);
        estimate = estimate.divDown(
            ONE.divDown(_estimatePrice) +
                _params.governanceFee.mulDown(_params.curveFee).mulDown(
                    ONE - _spotPrice
                ) -
                ONE -
                _params.curveFee.mulDown(ONE.divDown(_spotPrice) - ONE)
        );
        return estimate;
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
    /// @param _checkpointLongExposure The long exposure in the checkpoint.
    /// @param _baseAmount The base amount.
    /// @param _bondAmount The bond amount.
    /// @param _spotPrice The spot price.
    /// @return The solvency of the pool.
    /// @return A flag indicating that the pool is solvent if true and insolvent
    ///         if false.
    function calculateSolvencyAfterLong(
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
    /// @param _effectiveShareReserves The effective share reserves.
    /// @param _spotPrice The spot price.
    /// @return derivative The negation of the derivative of the pool's solvency
    ///         w.r.t the base amount.
    /// @return success A flag indicating whether or not the derivative was
    ///         successfully calculated.
    function calculateSolvencyAfterLongDerivative(
        MaxTradeParams memory _params,
        uint256 _baseAmount,
        uint256 _effectiveShareReserves,
        uint256 _spotPrice
    ) internal pure returns (uint256 derivative, bool success) {
        // Calculate the derivative of the long amount. This calculation can
        // fail when we are close to the root. In these cases, we exit early.
        (derivative, success) = calculateLongAmountDerivative(
            _params,
            _baseAmount,
            _effectiveShareReserves,
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
    ///                         \mu \cdot \left( z - \zeta + \tfrac{x}{c}
    ///                     \right) \right)^{1 - t_s}
    ///                 \right)^{\tfrac{1}{1 - t_s}}
    ///      $$
    /// @param _params The max long calculation parameters.
    /// @param _baseAmount The base amount.
    /// @param _effectiveShareReserves The effective share reserves.
    /// @param _spotPrice The spot price.
    /// @return The long amount.
    function calculateLongAmount(
        MaxTradeParams memory _params,
        uint256 _baseAmount,
        uint256 _effectiveShareReserves,
        uint256 _spotPrice
    ) internal pure returns (uint256) {
        uint256 longAmount = YieldSpaceMath.calculateBondsOutGivenSharesIn(
            _effectiveShareReserves,
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
    ///      y_{*}'(x) = \left( \mu \cdot (z - \zeta + \tfrac{x}{c}) \right)^{-t_s}
    ///                  \left(
    ///                      k - \tfrac{c}{\mu} \cdot
    ///                      \left(
    ///                          \mu \cdot (z - \zeta + \tfrac{x}{c}
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
    /// @param _effectiveShareReserves The effective share reserves.
    /// @return derivative The derivative of the long amount w.r.t. the base
    ///         amount.
    /// @return A flag indicating whether or not the derivative was
    ///         successfully calculated.
    function calculateLongAmountDerivative(
        MaxTradeParams memory _params,
        uint256 _baseAmount,
        uint256 _effectiveShareReserves,
        uint256 _spotPrice
    ) internal pure returns (uint256 derivative, bool) {
        // Compute the first part of the derivative.
        uint256 shareAmount = _baseAmount.divDown(_params.sharePrice);
        uint256 inner = _params.initialSharePrice.mulDown(
            _effectiveShareReserves + shareAmount
        );
        uint256 cDivMu = _params.sharePrice.divDown(_params.initialSharePrice);
        uint256 k = YieldSpaceMath.modifiedYieldSpaceConstant(
            cDivMu,
            _params.initialSharePrice,
            _effectiveShareReserves,
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

    /// @dev A struct used to hold extra variables in the max short calculation
    ///      function to avoid stack-too-deep errors.
    struct MaxShortInternal {
        uint256 solvency;
        uint256 derivative;
        bool success;
    }

    /// @dev Gets the absolute max short that can be opened without violating
    ///      the pool's solvency constraints.
    /// @param _checkpointExposure The long exposure in the current checkpoint.
    /// @return The maximum amount of shares that can be used to open shorts.
    function calculateMaxShort(
        MaxTradeParams memory _params,
        int256 _checkpointExposure,
        uint256 _maxIterations
    ) internal pure returns (uint256) {
        // We start by calculating the maximum short that can be opened on the
        // YieldSpace curve. Both $z \geq z_{min}$ and $z - \zeta \geq z_{min}$
        // must hold, which allows us to solve directly for the optimal bond
        // reserves.
        MaxShortInternal memory internal_;
        uint256 effectiveShareReserves = calculateEffectiveShareReserves(
            _params.shareReserves,
            _params.shareAdjustment
        );
        uint256 spotPrice = calculateSpotPrice(
            effectiveShareReserves,
            _params.bondReserves,
            _params.initialSharePrice,
            _params.timeStretch
        );
        uint256 absoluteMaxBondAmount = calculateMaxShortUpperBound(
            _params,
            effectiveShareReserves
        );
        (internal_.solvency, internal_.success) = calculateSolvencyAfterShort(
            _params,
            absoluteMaxBondAmount,
            effectiveShareReserves,
            spotPrice,
            _checkpointExposure
        );
        if (internal_.success) {
            return absoluteMaxBondAmount;
        }

        // Use Newton's method to iteratively approach a solution. We use pool's
        // solvency $S(x)$ w.r.t. the amount of bonds shorted $x$ as our
        // objective function, which will converge to the maximum short amount
        // when $S(x) = 0$. The derivative of $S(x)$ is negative (since solvency
        // decreases as more shorts are opened). The fixed point library doesn't
        // support negative numbers, so we use the negation of the derivative to
        // side-step the issue.
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
        uint256 maxBondAmount = calculateMaxShortGuess(
            _params,
            spotPrice,
            _checkpointExposure
        );
        (internal_.solvency, internal_.success) = calculateSolvencyAfterShort(
            _params,
            maxBondAmount,
            effectiveShareReserves,
            spotPrice,
            _checkpointExposure
        );
        require(
            internal_.success,
            "Initial guess in `calculateMaxShort` is insolvent"
        );
        for (uint256 i = 0; i < _maxIterations; i++) {
            // TODO: It may be better to gracefully handle crossing over the
            // root by extending the fixed point math library to handle negative
            // numbers or even just using an if-statement to handle the negative
            // numbers.
            //
            // Calculate the next iteration of Newton's method. If the candidate
            // is larger than the absolute max, we've gone too far and something
            // has gone wrong.
            (
                internal_.derivative,
                internal_.success
            ) = calculateSolvencyAfterShortDerivative(
                _params,
                maxBondAmount,
                spotPrice,
                effectiveShareReserves
            );
            if (!internal_.success) {
                break;
            }
            uint256 possibleMaxBondAmount = maxBondAmount +
                internal_.solvency.divDown(internal_.derivative);
            if (possibleMaxBondAmount > absoluteMaxBondAmount) {
                break;
            }

            // If the candidate is insolvent, we've gone too far and can stop
            // iterating. Otherwise, we update our guess and continue.
            (
                internal_.solvency,
                internal_.success
            ) = calculateSolvencyAfterShort(
                _params,
                possibleMaxBondAmount,
                effectiveShareReserves,
                spotPrice,
                _checkpointExposure
            );
            if (internal_.success) {
                maxBondAmount = possibleMaxBondAmount;
            } else {
                break;
            }
        }

        return maxBondAmount;
    }

    /// @dev Calculates the max short that can be opened on the YieldSpace curve
    ///      without considering solvency constraints.
    /// @param _params Information about the market state and pool configuration
    ///        used to compute the maximum trade.
    /// @param _effectiveShareReserves The effective share reserves.
    /// @return The max short YieldSpace can support without considering solvency.
    function calculateMaxShortUpperBound(
        MaxTradeParams memory _params,
        uint256 _effectiveShareReserves
    ) internal pure returns (uint256) {
        // We have the twin constraints that $z \geq z_{min}$ and
        // $z - \zeta \geq 0$. Combining these together, we can calculate the
        // optimal share reserves as $z_{optimal} = max(z_{min}, \zeta)$. We
        // run into problems when we get too close to $z - \zeta = 0$, so we
        // add a small adjustment to the optimal share reserves to ensure that
        // we don't run into any issues.
        uint256 optimalShareReserves = uint256(
            int256(_params.minimumShareReserves).max(
                _params.shareAdjustment + int256(_params.minimumShareReserves)
            )
        );

        // We calculate the optimal bond reserves by solving for the bond
        // reserves that is implied by the optimal share reserves. We can do
        // this as follows:
        //
        // $$
        // k = \tfrac{c}{\mu} \cdot \left(
        //          \mu \cdot \left( z_{optimal} - \zeta \right)
        //      \right)^{1 - t_s} + y_{optimal}^{1 - t_s} \\
        // \implies \\
        // y_{optimal} = \left(
        //                   k - \tfrac{c}{\mu} \cdot \left(
        //                       \mu \cdot \left( z_{optimal} - \zeta \right)
        //                   \right)^{1 - t_s}
        //               \right)^{\tfrac{1}{1 - t_s}}
        // $$
        uint256 k = YieldSpaceMath.modifiedYieldSpaceConstant(
            _params.sharePrice.divDown(_params.initialSharePrice),
            _params.initialSharePrice,
            _effectiveShareReserves,
            ONE - _params.timeStretch,
            _params.bondReserves
        );
        uint256 optimalBondReserves = (k -
            (_params.sharePrice.divDown(_params.initialSharePrice)).mulDown(
                _params
                    .initialSharePrice
                    .mulDown(
                        calculateEffectiveShareReserves(
                            optimalShareReserves,
                            _params.shareAdjustment
                        )
                    )
                    .pow(ONE - _params.timeStretch)
            )).pow(ONE.divUp(ONE - _params.timeStretch));

        return optimalBondReserves - _params.bondReserves;
    }

    /// @dev Gets an initial guess for the absolute max short. This is a
    ///      conservative guess that will be less than the true absolute max
    ///      short, which is what we need to start Newton's method.
    ///
    ///      To calculate our guess, we assume an unrealistically good realized
    ///      price $p_r$ for opening the short. This allows us to approximate
    ///      $P(x) \approx \tfrac{1}{c} \cdot p_r \cdot x$. Plugging this
    ///      into our solvency function $s(x)$, we get an approximation of our
    ///      solvency as:
    ///
    ///      $$
    ///      S(x) \approx (z_0 - \tfrac{1}{c} \cdot (
    ///                       p_r - \phi_{c} \cdot (1 - p) + \phi_{g} \cdot \phi_{c} \cdot (1 - p)
    ///                   ) \cdot x) - \tfrac{e_0 - max(e_{c}, 0)}{c} - z_{min}
    ///      $$
    ///
    ///      Setting this equal to zero, we can solve for our initial guess:
    ///
    ///      $$
    ///      x = \frac{c \cdot (s_0 + \tfrac{max(e_{c}, 0)}{c})}{
    ///              p_r - \phi_{c} \cdot (1 - p) + \phi_{g} \cdot \phi_{c} \cdot (1 - p)
    ///          }
    ///      $$
    /// @param _params Information about the market state and pool configuration
    ///        used to compute the maximum trade.
    /// @param _spotPrice The spot price.
    /// @param _checkpointExposure The long exposure from the current checkpoint.
    /// @return The initial guess for the max short calculation.
    function calculateMaxShortGuess(
        MaxTradeParams memory _params,
        uint256 _spotPrice,
        int256 _checkpointExposure
    ) internal pure returns (uint256) {
        uint256 estimatePrice = _spotPrice;
        uint256 guess = _params.sharePrice.mulDown(
            _params.shareReserves +
                uint256(_checkpointExposure.max(0)).divDown(
                    _params.sharePrice
                ) -
                _params.longExposure.divDown(_params.sharePrice) -
                _params.minimumShareReserves
        );
        return
            guess.divDown(
                estimatePrice -
                    _params.curveFee.mulDown(ONE - _spotPrice) +
                    _params.governanceFee.mulDown(_params.curveFee).mulDown(
                        ONE - _spotPrice
                    )
            );
    }

    /// @dev Gets the pool's solvency after opening a short.
    ///
    ///      We can express the pool's solvency after opening a short of $x$
    ///      bonds as:
    ///
    ///      $$
    ///      s(x) = z(x) - \tfrac{e(x)}{c} - z_{min}
    ///      $$
    ///
    ///      where $z(x)$ represents the pool's share reserves after opening the
    ///      short:
    ///
    ///      $$
    ///      z(x) = z_0 - \left(
    ///                 P(x) - \left( \tfrac{c(x)}{c} - \tfrac{g(x)}{c} \right)
    ///             \right)
    ///      $$
    ///
    ///      and $e(x)$ represents the pool's exposure after opening the short:
    ///
    ///      $$
    ///      e(x) = e_0 - min(x + D(x), max(e_{c}, 0))
    ///      $$
    ///
    ///      We simplify our $e(x)$ formula by noting that the max short is only
    ///      constrained by solvency when $x + D(x) > max(e_{c}, 0)$ since
    ///      $x + D(x)$ grows faster than
    ///      $P(x) - \tfrac{\phi_{c}}{c} \cdot \left( 1 - p \right) \cdot x$.
    ///      With this in mind, $min(x + D(x), max(e_{c}, 0)) = max(e_{c}, 0)$
    ///      whenever solvency is actually a constraint, so we can write:
    ///
    ///      $$
    ///      e(x) = e_0 - max(e_{c}, 0)
    ///      $$
    /// @param _params Information about the market state and pool configuration
    ///        used to compute the maximum trade.
    /// @param _shortAmount The short amount.
    /// @param _effectiveShareReserves The effective share reserves.
    /// @param _spotPrice The spot price.
    /// @param _checkpointExposure The long exposure in the current checkpoint.
    /// @return The pool's solvency after a short is opened.
    /// @return A flag indicating whether or not the derivative was
    ///         successfully calculated.
    function calculateSolvencyAfterShort(
        MaxTradeParams memory _params,
        uint256 _shortAmount,
        uint256 _effectiveShareReserves,
        uint256 _spotPrice,
        int256 _checkpointExposure
    ) internal pure returns (uint256, bool) {
        // Calculate the bond amount using the safe variant. If this fails, we
        // know that the short is not possible.
        (uint256 bondAmount, bool success) = YieldSpaceMath
            .calculateSharesOutGivenBondsInSafe(
                _effectiveShareReserves,
                _params.bondReserves,
                _shortAmount,
                ONE - _params.timeStretch,
                _params.sharePrice,
                _params.initialSharePrice
            );
        if (!success) {
            return (0, false);
        }

        // Calculate the pool's solvency after opening the short.
        uint256 shareReserves = _params.shareReserves -
            (bondAmount -
                (calculateShortCurveFee(
                    _shortAmount,
                    _spotPrice,
                    _params.curveFee
                ) -
                    calculateShortGovernanceFee(
                        _shortAmount,
                        _spotPrice,
                        _params.curveFee,
                        _params.governanceFee
                    )).divDown(_params.sharePrice));
        uint256 exposure = (_params.longExposure -
            uint256(_checkpointExposure.max(0))).divDown(_params.sharePrice);
        if (shareReserves >= exposure + _params.minimumShareReserves) {
            return (
                shareReserves - exposure - _params.minimumShareReserves,
                true
            );
        } else {
            return (0, false);
        }
    }

    /// @dev Gets the derivative of the pool's solvency w.r.t. the short amount.
    ///
    ///      The derivative is calculated as:
    ///
    ///      \begin{aligned}
    ///      s'(x) &= z'(x) - 0 - 0
    ///            &= 0 - \left( P'(x) - \frac{(c'(x) - g'(x))}{c} \right)
    ///            &= -P'(x) + \frac{
    ///                   \phi_{c} \cdot (1 - p) \cdot (1 - \phi_{g})
    ///               }{c}
    ///      \end{aligned}
    ///
    ///      Since solvency decreases as the short amount increases, we negate
    ///      the derivative. This avoids issues with the fixed point library
    ///      which doesn't support negative values.
    /// @return The derivative of the solvency after short function w.r.t. the
    ///         bond amount.
    /// @return A flag indicating whether or not the derivative was
    ///         successfully calculated.
    function calculateSolvencyAfterShortDerivative(
        MaxTradeParams memory _params,
        uint256 _shortAmount,
        uint256 _spotPrice,
        uint256 _effectiveShareReserves
    ) internal pure returns (uint256, bool) {
        uint256 lhs = calculateShortPrincipalDerivative(
            _params,
            _shortAmount,
            _effectiveShareReserves
        );
        uint256 rhs = _params
            .curveFee
            .mulDown(ONE - _spotPrice)
            .mulDown(ONE - _params.governanceFee)
            .divDown(_params.sharePrice);
        if (lhs >= rhs) {
            return (lhs - rhs, true);
        } else {
            return (0, false);
        }
    }

    /// @dev Gets the derivative of the short principal $P(x)$ w.r.t. the amount
    ///      of bonds that are shorted $x$.
    ///
    ///      The derivative is calculated as:
    ///
    ///      $$
    ///      P'(x) = \tfrac{1}{c} \cdot (y + x)^{-t_s} \cdot \left(
    ///                  \tfrac{\mu}{c} \cdot (k - (y + x)^{1 - t_s})
    ///              \right)^{\tfrac{t_s}{1 - t_s}}
    ///      $$
    /// @param _params The max long calculation parameters.
    /// @param _shortAmount The base amount.
    /// @param _effectiveShareReserves The effective share reserves.
    /// @return The derivative of the short principal w.r.t. the bond amount.
    function calculateShortPrincipalDerivative(
        MaxTradeParams memory _params,
        uint256 _shortAmount,
        uint256 _effectiveShareReserves
    ) internal pure returns (uint256) {
        uint256 k = YieldSpaceMath.modifiedYieldSpaceConstant(
            _params.sharePrice.divDown(_params.initialSharePrice),
            _params.initialSharePrice,
            _effectiveShareReserves,
            ONE - _params.timeStretch,
            _params.bondReserves
        );
        uint256 lhs = ONE.divDown(
            _params.sharePrice.mulUp(
                (_params.bondReserves + _shortAmount).pow(_params.timeStretch)
            )
        );
        uint256 rhs = _params
            .initialSharePrice
            .divDown(_params.sharePrice)
            .mulDown(
                k -
                    (_params.bondReserves + _shortAmount).pow(
                        ONE - _params.timeStretch
                    )
            )
            .pow(_params.timeStretch.divUp(ONE - _params.timeStretch));
        return lhs.mulDown(rhs);
    }

    /// @dev Gets the curve fee paid by the trader when they open a short.
    /// @param _bondAmount The bond amount.
    /// @param _spotPrice The spot price.
    /// @param _curveFee The curve fee parameter.
    /// @return The curve fee.
    function calculateShortCurveFee(
        uint256 _bondAmount,
        uint256 _spotPrice,
        uint256 _curveFee
    ) internal pure returns (uint256) {
        return _curveFee.mulDown(ONE - _spotPrice).mulDown(_bondAmount);
    }

    /// @dev Gets the governance fee paid by the trader when they open a short.
    /// @param _bondAmount The bond amount.
    /// @param _spotPrice The spot price.
    /// @param _curveFee The curve fee parameter.
    /// @param _governanceFee The governance fee parameter.
    /// @return The governance fee.
    function calculateShortGovernanceFee(
        uint256 _bondAmount,
        uint256 _spotPrice,
        uint256 _curveFee,
        uint256 _governanceFee
    ) internal pure returns (uint256) {
        return
            _governanceFee.mulDown(
                calculateShortCurveFee(_bondAmount, _spotPrice, _curveFee)
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
        uint256 effectiveShareReserves = calculateEffectiveShareReserves(
            _params.shareReserves,
            _params.shareAdjustment
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
                effectiveShareReserves,
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
                        effectiveShareReserves,
                        _params.bondReserves,
                        maxCurveTrade,
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
                effectiveShareReserves,
                _params.bondReserves,
                ONE - _params.timeStretch,
                _params.sharePrice,
                _params.initialSharePrice
            );
            maxCurveTrade = maxCurveTrade.min(uint256(netCurveTrade)); // netCurveTrade is positive, so this is safe.
            if (maxCurveTrade > 0) {
                _params.shareReserves += YieldSpaceMath
                    .calculateSharesInGivenBondsOut(
                        effectiveShareReserves,
                        _params.bondReserves,
                        maxCurveTrade,
                        ONE - _params.timeStretch,
                        _params.sharePrice,
                        _params.initialSharePrice
                    );
            }
            _params.shareReserves += uint256(netCurveTrade) - maxCurveTrade;
        }

        // Compute the net of the longs and shorts that will be traded flat and
        // apply this net to the reserves.
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
        int256 updatedShareReserves = int256(_params.shareReserves) +
            netFlatTrade;
        if (updatedShareReserves < int256(_params.minimumShareReserves)) {
            revert IHyperdrive.NegativePresentValue();
        }
        _params.shareReserves = uint256(updatedShareReserves);

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

    /// @dev Calculates the effective share reserves. The effective share
    ///      reserves are the share reserves minus the share adjustment or
    ///      z - zeta. We use the effective share reserves as the z-parameter
    ///      to the YieldSpace pricing model. The share adjustment is used to
    ///      hold the pricing mechanism invariant under the flat component of
    ///      flat+curve trades.
    /// @param _shareReserves The pool's share reserves.
    /// @param _shareAdjustment The pool's share adjustment.
    /// @return The effective share reserves.
    function calculateEffectiveShareReserves(
        uint256 _shareReserves,
        int256 _shareAdjustment
    ) internal pure returns (uint256) {
        int256 effectiveShareReserves = int256(_shareReserves) -
            _shareAdjustment;
        require(effectiveShareReserves >= 0);
        return uint256(effectiveShareReserves);
    }
}
