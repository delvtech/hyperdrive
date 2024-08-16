// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../contracts/src/libraries/HyperdriveMath.sol";
import { LPMath } from "../../contracts/src/libraries/LPMath.sol";
import { YieldSpaceMath } from "../../contracts/src/libraries/YieldSpaceMath.sol";

library HyperdriveUtils {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using HyperdriveUtils for *;
    using LPMath for LPMath.PresentValueParams;

    /// Time Utilities ///

    function latestCheckpoint(
        IHyperdrive hyperdrive
    ) internal view returns (uint256) {
        return
            block.timestamp -
            (block.timestamp % hyperdrive.getPoolConfig().checkpointDuration);
    }

    function calculateTimeRemaining(
        IHyperdrive _hyperdrive,
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        timeRemaining = _maturityTime > latestCheckpoint(_hyperdrive)
            ? _maturityTime - latestCheckpoint(_hyperdrive)
            : 0;
        timeRemaining = timeRemaining.divDown(
            _hyperdrive.getPoolConfig().positionDuration
        );
        return timeRemaining;
    }

    function maturityTimeFromLatestCheckpoint(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        return
            latestCheckpoint(_hyperdrive) +
            _hyperdrive.getPoolConfig().positionDuration;
    }

    /// Price and Rate Utils ///

    function calculateSpotPrice(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        return
            HyperdriveMath.calculateSpotPrice(
                HyperdriveMath.calculateEffectiveShareReserves(
                    poolInfo.shareReserves,
                    poolInfo.shareAdjustment
                ),
                poolInfo.bondReserves,
                poolConfig.initialVaultSharePrice,
                poolConfig.timeStretch
            );
    }

    function calculateSpotAPR(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        return
            HyperdriveMath.calculateSpotAPR(
                HyperdriveMath.calculateEffectiveShareReserves(
                    poolInfo.shareReserves,
                    poolInfo.shareAdjustment
                ),
                poolInfo.bondReserves,
                poolConfig.initialVaultSharePrice,
                poolConfig.positionDuration,
                poolConfig.timeStretch
            );
    }

    function calculateAPRFromRealizedPrice(
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 timeRemaining
    ) internal pure returns (uint256) {
        // price = dx / dy
        //       =>
        // rate = (1 - p) / (p * t) = (1 - dx / dy) * (dx / dy * t)
        //       =>
        // apr = (dy - dx) / (dx * t)
        require(
            timeRemaining <= 1e18 && timeRemaining > 0,
            "Expecting NormalizedTimeRemaining"
        );
        return
            (bondAmount - baseAmount).divDown(
                baseAmount.mulDown(timeRemaining)
            );
    }

    /// @dev Calculates the non-compounded interest over a period.
    /// @param _principal The principal amount that will accrue interest.
    /// @param _apr Annual percentage rate
    /// @param _time Amount of time in seconds over which interest accrues.
    /// @return totalAmount The total amount of capital after interest accrues.
    /// @return interest The interest that accrued.
    function calculateInterest(
        uint256 _principal,
        int256 _apr,
        uint256 _time
    ) internal pure returns (uint256 totalAmount, int256 interest) {
        // Adjust time to a fraction of a year
        uint256 normalizedTime = _time.divDown(365 days);
        interest = _apr >= 0
            ? int256(_principal.mulDown(uint256(_apr).mulDown(normalizedTime)))
            : -int256(
                _principal.mulDown(uint256(-_apr).mulDown(normalizedTime))
            );
        totalAmount = uint256(int256(_principal) + interest);
        return (totalAmount, interest);
    }

    /// @dev Calculates principal + compounded rate of interest over a period
    ///      principal * e ^ (rate * time)
    /// @param _principal The initial amount interest will be accrued on
    /// @param _rate Interest rate
    /// @param _time Number of seconds compounding will occur for
    /// @return totalAmount The total amount of capital after interest accrues.
    /// @return interest The interest that accrued.
    function calculateCompoundInterest(
        uint256 _principal,
        int256 _rate,
        uint256 _time
    ) internal pure returns (uint256 totalAmount, int256 interest) {
        // Adjust time to a fraction of a year
        uint256 normalizedTime = _time.divDown(365 days);
        uint256 rt = uint256(_rate < 0 ? -_rate : _rate).mulDown(
            normalizedTime
        );

        if (_rate > 0) {
            totalAmount = _principal.mulDown(
                uint256(FixedPointMath.exp(int256(rt)))
            );
            interest = int256(totalAmount - _principal);
            return (totalAmount, interest);
        } else if (_rate < 0) {
            // NOTE: Might not be the correct calculation for negatively
            // continuously compounded interest
            totalAmount = _principal.divDown(
                uint256(FixedPointMath.exp(int256(rt)))
            );
            interest = int256(totalAmount) - int256(_principal);
            return (totalAmount, interest);
        }
        return (_principal, 0);
    }

    /// Trade Utils ///

    /// @dev Calculates the maximum amount of longs that can be opened.
    /// @param _hyperdrive A Hyperdrive instance.
    /// @param _maxIterations The maximum number of iterations to use.
    /// @return baseAmount The cost of buying the maximum amount of longs.
    function calculateMaxLong(
        IHyperdrive _hyperdrive,
        uint256 _maxIterations
    ) internal view returns (uint256 baseAmount) {
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        (baseAmount, ) = calculateMaxLong(
            MaxTradeParams({
                shareReserves: poolInfo.shareReserves,
                shareAdjustment: poolInfo.shareAdjustment,
                bondReserves: poolInfo.bondReserves,
                longsOutstanding: poolInfo.longsOutstanding,
                longExposure: poolInfo.longExposure,
                timeStretch: poolConfig.timeStretch,
                vaultSharePrice: poolInfo.vaultSharePrice,
                initialVaultSharePrice: poolConfig.initialVaultSharePrice,
                minimumShareReserves: poolConfig.minimumShareReserves,
                curveFee: poolConfig.fees.curve,
                flatFee: poolConfig.fees.flat,
                governanceLPFee: poolConfig.fees.governanceLP
            }),
            _hyperdrive.getCheckpointExposure(_hyperdrive.latestCheckpoint()),
            _maxIterations
        );
        return baseAmount;
    }

    /// @dev Calculates the maximum amount of longs that can be opened.
    /// @param _hyperdrive A Hyperdrive instance.
    /// @return baseAmount The cost of buying the maximum amount of longs.
    function calculateMaxLong(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256 baseAmount) {
        return calculateMaxLong(_hyperdrive, 7);
    }

    /// @dev Calculates the maximum amount of shorts that can be opened.
    /// @param _hyperdrive A Hyperdrive instance.
    /// @param _maxIterations The maximum number of iterations to use.
    /// @return The maximum amount of bonds that can be shorted.
    function calculateMaxShort(
        IHyperdrive _hyperdrive,
        uint256 _maxIterations
    ) internal view returns (uint256) {
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        return
            calculateMaxShort(
                MaxTradeParams({
                    shareReserves: poolInfo.shareReserves,
                    shareAdjustment: poolInfo.shareAdjustment,
                    bondReserves: poolInfo.bondReserves,
                    longsOutstanding: poolInfo.longsOutstanding,
                    longExposure: poolInfo.longExposure,
                    timeStretch: poolConfig.timeStretch,
                    vaultSharePrice: poolInfo.vaultSharePrice,
                    initialVaultSharePrice: poolConfig.initialVaultSharePrice,
                    minimumShareReserves: poolConfig.minimumShareReserves,
                    curveFee: poolConfig.fees.curve,
                    flatFee: poolConfig.fees.flat,
                    governanceLPFee: poolConfig.fees.governanceLP
                }),
                _hyperdrive.getCheckpointExposure(
                    _hyperdrive.latestCheckpoint()
                ),
                _maxIterations
            );
    }

    /// @dev Calculates the maximum amount of shorts that can be opened.
    /// @param _hyperdrive A Hyperdrive instance.
    /// @return The maximum amount of bonds that can be shorted.
    function calculateMaxShort(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        return calculateMaxShort(_hyperdrive, 7);
    }

    struct MaxTradeParams {
        uint256 shareReserves;
        int256 shareAdjustment;
        uint256 bondReserves;
        uint256 longsOutstanding;
        uint256 longExposure;
        uint256 timeStretch;
        uint256 vaultSharePrice;
        uint256 initialVaultSharePrice;
        uint256 minimumShareReserves;
        uint256 curveFee;
        uint256 flatFee;
        uint256 governanceLPFee;
    }

    /// @dev Gets the max long that can be opened given a budget.
    ///
    ///      We start by calculating the long that brings the pool's spot price
    ///      to 1. If we are solvent at this point, then we're done. Otherwise,
    ///      we approach the max long iteratively using Newton's method.
    /// @param _params The parameters for the max long calculation.
    /// @param _checkpointExposure The exposure in the checkpoint.
    /// @param _maxIterations The maximum number of iterations to use in the
    ///                       Newton's method loop.
    /// @return maxBaseAmount The maximum base amount.
    /// @return maxBondAmount The maximum bond amount.
    function calculateMaxLong(
        MaxTradeParams memory _params,
        int256 _checkpointExposure,
        uint256 _maxIterations
    ) internal pure returns (uint256 maxBaseAmount, uint256 maxBondAmount) {
        // Get the maximum long that brings the spot price to 1. If the pool is
        // solvent after opening this long, then we're done.
        uint256 effectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                _params.shareReserves,
                _params.shareAdjustment
            );
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            effectiveShareReserves,
            _params.bondReserves,
            _params.initialVaultSharePrice,
            _params.timeStretch
        );
        uint256 absoluteMaxBaseAmount;
        uint256 absoluteMaxBondAmount;
        {
            (
                absoluteMaxBaseAmount,
                absoluteMaxBondAmount
            ) = calculateAbsoluteMaxLong(
                _params,
                effectiveShareReserves,
                spotPrice
            );
            (, bool isSolvent_) = calculateSolvencyAfterLong(
                _params,
                _checkpointExposure,
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
            _checkpointExposure,
            spotPrice
        );
        maxBondAmount = calculateLongAmount(
            _params,
            maxBaseAmount,
            effectiveShareReserves,
            spotPrice
        );
        (uint256 solvency_, bool success) = calculateSolvencyAfterLong(
            _params,
            _checkpointExposure,
            maxBaseAmount,
            maxBondAmount,
            spotPrice
        );
        require(success, "Initial guess in `calculateMaxLong` is insolvent.");
        for (uint256 i = 0; i < _maxIterations; ++i) {
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
                solvency_.divDown(derivative);
            uint256 possibleMaxBondAmount = calculateLongAmount(
                _params,
                possibleMaxBaseAmount,
                effectiveShareReserves,
                spotPrice
            );
            (solvency_, success) = calculateSolvencyAfterLong(
                _params,
                _checkpointExposure,
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

    /// @dev Calculates the largest long that can be opened without buying bonds
    ///      at a negative interest rate. This calculation does not take
    ///      Hyperdrive's solvency constraints into account and shouldn't be
    ///      used directly.
    /// @param _params The parameters for the max long calculation.
    /// @param _effectiveShareReserves The pool's effective share reserves.
    /// @param _spotPrice The pool's spot price.
    /// @return absoluteMaxBaseAmount The absolute maximum base amount.
    /// @return absoluteMaxBondAmount The absolute maximum bond amount.
    function calculateAbsoluteMaxLong(
        MaxTradeParams memory _params,
        uint256 _effectiveShareReserves,
        uint256 _spotPrice
    )
        internal
        pure
        returns (uint256 absoluteMaxBaseAmount, uint256 absoluteMaxBondAmount)
    {
        // We are targeting the pool's max spot price of:
        //
        // p_max = (1 - flatFee) / (1 + curveFee * (1 / p_0 - 1) * (1 - flatFee))
        //
        // We can derive a formula for the target bond reserves y_t in
        // terms of the target share reserves z_t as follows:
        //
        // p_max = ((mu * z_t) / y_t) ** t_s
        //
        //                       =>
        //
        // y_t = (mu * z_t) * ((1 + curveFee * (1 / p_0 - 1) * (1 - flatFee)) / (1 - flatFee)) ** (1 / t_s)
        //
        // We can use this formula to solve our YieldSpace invariant for z_t:
        //
        // k = (c / mu) * (mu * z_t) ** (1 - t_s) +
        //     (
        //         (mu * z_t) * ((1 + curveFee * (1 / p_0 - 1) * (1 - flatFee)) / (1 - flatFee)) ** (1 / t_s)
        //     ) ** (1 - t_s)
        //
        //                       =>
        //
        // z_t = (1 / mu) * (
        //           k / (
        //               (c / mu) +
        //               ((1 + curveFee * (1 / p_0 - 1) * (1 - flatFee)) / (1 - flatFee)) ** ((1 - t_s) / t_s))
        //           )
        //       ) ** (1 / (1 - t_s))
        uint256 inner;
        {
            uint256 k_ = YieldSpaceMath.kDown(
                _effectiveShareReserves,
                _params.bondReserves,
                ONE - _params.timeStretch,
                _params.vaultSharePrice,
                _params.initialVaultSharePrice
            );
            inner = _params.curveFee.mulUp(ONE.divUp(_spotPrice) - ONE).mulUp(
                ONE - _params.flatFee
            );
            inner = (ONE + inner).divUp(ONE - _params.flatFee);
            inner = inner.pow(
                (ONE - _params.timeStretch).divDown(_params.timeStretch)
            );
            inner += _params.vaultSharePrice.divUp(
                _params.initialVaultSharePrice
            );
            inner = k_.divDown(inner);
            inner = inner.pow(ONE.divDown(ONE - _params.timeStretch));
        }
        uint256 targetShareReserves = inner.divDown(
            _params.initialVaultSharePrice
        );

        // Now that we have the target share reserves, we can calculate the
        // target bond reserves using the formula:
        //
        // y_t = (mu * z_t) * ((1 + curveFee * (1 / p_0 - 1) * (1 - flatFee)) / (1 - flatFee)) ** (1 / t_s)
        //
        // Here we round down to underestimate the number of bonds that can be longed.
        uint256 targetBondReserves;
        {
            uint256 feeAdjustment = _params
                .curveFee
                .mulDown(ONE.divDown(_spotPrice) - ONE)
                .mulDown(ONE - _params.flatFee);
            targetBondReserves = (
                (ONE + feeAdjustment).divDown(ONE - _params.flatFee)
            ).pow(ONE.divUp(_params.timeStretch)).mulDown(inner);
        }

        // The absolute max base amount is given by:
        //
        // absoluteMaxBaseAmount = c * (z_t - z)
        absoluteMaxBaseAmount = (targetShareReserves - _effectiveShareReserves)
            .mulDown(_params.vaultSharePrice);

        // The absolute max bond amount is given by:
        //
        // absoluteMaxBondAmount = (y - y_t) - c(x)
        absoluteMaxBondAmount =
            (_params.bondReserves - targetBondReserves) -
            calculateLongCurveFee(
                absoluteMaxBaseAmount,
                _spotPrice,
                _params.curveFee
            );
    }

    /// @dev Calculates an initial guess of the max long that can be opened.
    ///      This is a reasonable estimate that is guaranteed to be less than
    ///      the true max long. We use this to get a reasonable starting point
    ///      for Newton's method.
    /// @param _params The max long calculation parameters.
    /// @param _absoluteMaxBaseAmount The absolute max base amount that can be
    ///        used to open a long.
    /// @param _checkpointExposure The exposure in the checkpoint.
    /// @param _spotPrice The spot price of the pool.
    /// @return A conservative estimate of the max long that the pool can open.
    function calculateMaxLongGuess(
        MaxTradeParams memory _params,
        uint256 _absoluteMaxBaseAmount,
        int256 _checkpointExposure,
        uint256 _spotPrice
    ) internal pure returns (uint256) {
        // Get an initial estimate of the max long by using the spot price as
        // our conservative price.
        uint256 guess = calculateMaxLongEstimate(
            _params,
            _checkpointExposure,
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

        // Recalculate our initial guess using the bootstrapped conservative.
        // estimate of the realized price.
        guess = calculateMaxLongEstimate(
            _params,
            _checkpointExposure,
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
    ///      from non-netted shorts in the checkpoint. These formulas allow us
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
    /// @param _checkpointExposure The exposure in the checkpoint.
    /// @param _spotPrice The spot price of the pool.
    /// @param _estimatePrice The estimated realized price the max long will pay.
    /// @return A conservative estimate of the max long that the pool can open.
    function calculateMaxLongEstimate(
        MaxTradeParams memory _params,
        int256 _checkpointExposure,
        uint256 _spotPrice,
        uint256 _estimatePrice
    ) internal pure returns (uint256) {
        uint256 checkpointExposure = uint256(-_checkpointExposure.min(0));
        uint256 estimate = (_params.shareReserves +
            checkpointExposure.divDown(_params.vaultSharePrice) -
            _params.longExposure.divDown(_params.vaultSharePrice) -
            _params.minimumShareReserves).mulDivDown(
                _params.vaultSharePrice,
                2e18
            );
        estimate = estimate.divDown(
            ONE.divDown(_estimatePrice) +
                _params.governanceLPFee.mulDown(_params.curveFee).mulDown(
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
    ///      the global exposure variable by any negative exposure we have
    ///      in the checkpoint. The pool's solvency is calculated as:
    ///
    ///      $$
    ///      s = z - \tfrac{exposure + min(exposure_{checkpoint}, 0)}{c} - z_{min}
    ///      $$
    ///
    ///      When a long is opened, the share reserves $z$ increase by:
    ///
    ///      $$
    ///      \Delta z = \tfrac{x - g(x)}{c}
    ///      $$
    ///
    ///      Opening the long increases the non-netted longs by the bond amount.
    ///      From this, the change in the exposure is given by:
    ///
    ///      $$
    ///      \Delta exposure = y(x)
    ///      $$
    ///
    ///      From this, we can calculate $S(x)$ as:
    ///
    ///      $$
    ///      S(x) = \left( z + \Delta z \right) - \left(
    ///                 \tfrac{
    ///                     exposure +
    ///                     min(exposure_{checkpoint}, 0) +
    ///                     \Delta exposure
    ///                 }{c}
    ///             \right) - z_{min}
    ///      $$
    ///
    ///      It's possible that the pool is insolvent after opening a long. In
    ///      this case, we return `None` since the fixed point library can't
    ///      represent negative numbers.
    /// @param _params The max long calculation parameters.
    /// @param _checkpointExposure The exposure in the checkpoint.
    /// @param _baseAmount The base amount.
    /// @param _bondAmount The bond amount.
    /// @param _spotPrice The spot price.
    /// @return The solvency of the pool.
    /// @return A flag indicating that the pool is solvent if true and insolvent
    ///         if false.
    function calculateSolvencyAfterLong(
        MaxTradeParams memory _params,
        int256 _checkpointExposure,
        uint256 _baseAmount,
        uint256 _bondAmount,
        uint256 _spotPrice
    ) internal pure returns (uint256, bool) {
        uint256 governanceFee = calculateLongGovernanceFee(
            _baseAmount,
            _spotPrice,
            _params.curveFee,
            _params.governanceLPFee
        );
        uint256 shareReserves = _params.shareReserves +
            _baseAmount.divDown(_params.vaultSharePrice) -
            governanceFee.divDown(_params.vaultSharePrice);
        uint256 exposure = _params.longExposure + _bondAmount;
        uint256 checkpointExposure = uint256(-_checkpointExposure.min(0));
        if (
            shareReserves +
                checkpointExposure.divDown(_params.vaultSharePrice) >=
            exposure.divDown(_params.vaultSharePrice) +
                _params.minimumShareReserves
        ) {
            return (
                shareReserves +
                    checkpointExposure.divDown(_params.vaultSharePrice) -
                    exposure.divDown(_params.vaultSharePrice) -
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
    ///      S'(x) = \tfrac{1}{c} \cdot \left(
    ///                  1 - y'(x) - \phi_{g} \cdot p \cdot c'(x)
    ///              \right) \\
    ///            = \tfrac{1}{c} \cdot \left(
    ///                  1 - y'(x) - \phi_{g} \cdot \phi_{c} \cdot \left(
    ///                      1 - p
    ///                  \right)
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
        derivative += _params.governanceLPFee.mulDown(_params.curveFee).mulDown(
            ONE - _spotPrice
        );
        derivative -= ONE;

        return (derivative.mulDivDown(1e18, _params.vaultSharePrice), success);
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
        uint256 longAmount = HyperdriveMath.calculateOpenLong(
            _effectiveShareReserves,
            _params.bondReserves,
            _baseAmount.divDown(_params.vaultSharePrice),
            _params.timeStretch,
            _params.vaultSharePrice,
            _params.initialVaultSharePrice
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
        uint256 shareAmount = _baseAmount.divDown(_params.vaultSharePrice);
        uint256 inner = _params.initialVaultSharePrice.mulDown(
            _effectiveShareReserves + shareAmount
        );
        uint256 k_ = YieldSpaceMath.kDown(
            _effectiveShareReserves,
            _params.bondReserves,
            ONE - _params.timeStretch,
            _params.vaultSharePrice,
            _params.initialVaultSharePrice
        );
        derivative = ONE.divDown(inner.pow(_params.timeStretch));

        // It's possible that k is slightly larger than the rhs in the inner
        // calculation. If this happens, we are close to the root, and we short
        // circuit.
        uint256 rhs = _params.vaultSharePrice.mulDivDown(
            inner.pow(_params.timeStretch),
            _params.initialVaultSharePrice
        );
        if (k_ < rhs) {
            return (0, false);
        }
        derivative = derivative.mulDown(
            (k_ - rhs).pow(_params.timeStretch.divUp(ONE - _params.timeStretch))
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
        return _curveFee.mulUp(ONE.divUp(_spotPrice) - ONE).mulUp(_baseAmount);
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
    /// @param _governanceLPFee The governance fee, $\phi_{g}$.
    function calculateLongGovernanceFee(
        uint256 _baseAmount,
        uint256 _spotPrice,
        uint256 _curveFee,
        uint256 _governanceLPFee
    ) internal pure returns (uint256) {
        return
            calculateLongCurveFee(_baseAmount, _spotPrice, _curveFee)
                .mulDown(_governanceLPFee)
                .mulDown(_spotPrice);
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
        uint256 effectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                _params.shareReserves,
                _params.shareAdjustment
            );
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            effectiveShareReserves,
            _params.bondReserves,
            _params.initialVaultSharePrice,
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
        for (uint256 i = 0; i < _maxIterations; ++i) {
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
        // $z - \zeta \geq z_{min}$. Combining these together, we calculate the
        // optimal share reserves as $z_{optimal} = z_{min} + max(0, \zeta)$.
        uint256 optimalShareReserves = _params.minimumShareReserves +
            uint256(_params.shareAdjustment.max(0));

        // We calculate the optimal bond reserves by solving for the bond
        // reserves that is implied by the optimal share reserves. We can do
        // this as follows:
        //
        // k = (c / mu) * (mu * (z' - zeta)) ** (1 - t_s) + y' ** (1 - t_s)
        //                              =>
        // y' = (k - (c / mu) * (mu * (z' - zeta)) ** (1 - t_s)) ** (1 / (1 - t_s))
        uint256 k_ = YieldSpaceMath.kDown(
            _effectiveShareReserves,
            _params.bondReserves,
            ONE - _params.timeStretch,
            _params.vaultSharePrice,
            _params.initialVaultSharePrice
        );
        uint256 optimalBondReserves = k_ -
            _params.vaultSharePrice.mulDivUp(
                _params
                    .initialVaultSharePrice
                    .mulUp(
                        HyperdriveMath.calculateEffectiveShareReserves(
                            optimalShareReserves,
                            _params.shareAdjustment
                        )
                    )
                    .pow(ONE - _params.timeStretch),
                _params.initialVaultSharePrice
            );
        if (optimalBondReserves >= ONE) {
            // Rounding the exponent down results in a smaller outcome.
            optimalBondReserves = optimalBondReserves.pow(
                ONE.divDown(ONE - _params.timeStretch)
            );
        } else {
            // Rounding the exponent up results in a smaller outcome.
            optimalBondReserves = optimalBondReserves.pow(
                ONE.divUp(ONE - _params.timeStretch)
            );
        }

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
    /// @param _checkpointExposure The exposure from the current checkpoint.
    /// @return The initial guess for the max short calculation.
    function calculateMaxShortGuess(
        MaxTradeParams memory _params,
        uint256 _spotPrice,
        int256 _checkpointExposure
    ) internal pure returns (uint256) {
        uint256 estimatePrice = _spotPrice;
        uint256 guess = _params.vaultSharePrice.mulDown(
            _params.shareReserves +
                uint256(_checkpointExposure.max(0)).divDown(
                    _params.vaultSharePrice
                ) -
                _params.longExposure.divDown(_params.vaultSharePrice) -
                _params.minimumShareReserves
        );
        return
            guess.divDown(
                estimatePrice -
                    _params.curveFee.mulDown(ONE - _spotPrice) +
                    _params.governanceLPFee.mulDown(_params.curveFee).mulDown(
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
    ///      e(x) = e_0 - min(x, max(e_{c}, 0))
    ///      $$
    ///
    ///      We simplify our $e(x)$ formula by noting that the max short is only
    ///      constrained by solvency when $x > max(e_{c}, 0)$ since $x$ grows
    ///      faster than
    ///      $P(x) - \tfrac{\phi_{c}}{c} \cdot \left( 1 - p \right) \cdot x$.
    ///      With this in mind, $min(x, max(e_{c}, 0)) = max(e_{c}, 0)$
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
    /// @param _checkpointExposure The exposure in the current checkpoint.
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
        // Calculate the share amount using the safe variant. If this fails, we
        // know that the short is not possible.
        //
        // NOTE: We underestimate here to match the behavior of
        // `calculateOpenShort`.
        (uint256 shareAmount, bool success) = YieldSpaceMath
            .calculateSharesOutGivenBondsInDownSafe(
                _effectiveShareReserves,
                _params.bondReserves,
                _shortAmount,
                ONE - _params.timeStretch,
                _params.vaultSharePrice,
                _params.initialVaultSharePrice
            );
        if (!success) {
            return (0, false);
        }

        // Calculate the pool's solvency after opening the short.
        uint256 totalCurveFee = (calculateShortCurveFee(
            _shortAmount,
            _spotPrice,
            _params.curveFee
        ) -
            calculateShortGovernanceFee(
                _shortAmount,
                _spotPrice,
                _params.curveFee,
                _params.governanceLPFee
            )).divUp(_params.vaultSharePrice);
        if (shareAmount < totalCurveFee) {
            return (0, false);
        }
        uint256 shareReservesDelta = shareAmount - totalCurveFee;
        if (_params.shareReserves < shareReservesDelta) {
            return (0, false);
        }
        uint256 shareReserves = _params.shareReserves - shareReservesDelta;
        uint256 exposure = (_params.longExposure -
            uint256(_checkpointExposure.max(0))).divDown(
                _params.vaultSharePrice
            );
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
            .mulDown(ONE - _params.governanceLPFee)
            .divDown(_params.vaultSharePrice);
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
        uint256 k_ = YieldSpaceMath.kDown(
            _effectiveShareReserves,
            _params.bondReserves,
            ONE - _params.timeStretch,
            _params.vaultSharePrice,
            _params.initialVaultSharePrice
        );
        uint256 lhs = ONE.divDown(
            _params.vaultSharePrice.mulUp(
                (_params.bondReserves + _shortAmount).pow(_params.timeStretch)
            )
        );
        uint256 rhs = _params
            .initialVaultSharePrice
            .divDown(_params.vaultSharePrice)
            .mulDown(
                k_ -
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
        return _curveFee.mulUp(ONE - _spotPrice).mulUp(_bondAmount);
    }

    /// @dev Gets the governance fee paid by the trader when they open a short.
    /// @param _bondAmount The bond amount.
    /// @param _spotPrice The spot price.
    /// @param _curveFee The curve fee parameter.
    /// @param _governanceLPFee The governance fee parameter.
    /// @return The governance fee.
    function calculateShortGovernanceFee(
        uint256 _bondAmount,
        uint256 _spotPrice,
        uint256 _curveFee,
        uint256 _governanceLPFee
    ) internal pure returns (uint256) {
        return
            calculateShortCurveFee(_bondAmount, _spotPrice, _curveFee).mulDown(
                _governanceLPFee
            );
    }

    /// LP Utils ///

    function getPresentValueParams(
        IHyperdrive hyperdrive
    ) internal view returns (LPMath.PresentValueParams memory) {
        IHyperdrive.PoolConfig memory poolConfig = hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        return
            LPMath.PresentValueParams({
                shareReserves: poolInfo.shareReserves,
                shareAdjustment: poolInfo.shareAdjustment,
                bondReserves: poolInfo.bondReserves,
                vaultSharePrice: poolInfo.vaultSharePrice,
                initialVaultSharePrice: poolConfig.initialVaultSharePrice,
                minimumShareReserves: poolConfig.minimumShareReserves,
                minimumTransactionAmount: poolConfig.minimumTransactionAmount,
                timeStretch: poolConfig.timeStretch,
                longsOutstanding: poolInfo.longsOutstanding,
                longAverageTimeRemaining: calculateTimeRemaining(
                    hyperdrive,
                    uint256(poolInfo.longAverageMaturityTime).divUp(1e36)
                ),
                shortsOutstanding: poolInfo.shortsOutstanding,
                shortAverageTimeRemaining: calculateTimeRemaining(
                    hyperdrive,
                    uint256(poolInfo.shortAverageMaturityTime).divUp(1e36)
                )
            });
    }

    function getDistributeExcessIdleParams(
        IHyperdrive hyperdrive
    ) internal view returns (LPMath.DistributeExcessIdleParams memory) {
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        LPMath.PresentValueParams memory presentValueParams = hyperdrive
            .getPresentValueParams();
        uint256 startingPresentValue = LPMath.calculatePresentValue(
            presentValueParams
        );
        int256 netCurveTrade = int256(
            presentValueParams.longsOutstanding.mulDown(
                presentValueParams.longAverageTimeRemaining
            )
        ) -
            int256(
                presentValueParams.shortsOutstanding.mulDown(
                    presentValueParams.shortAverageTimeRemaining
                )
            );
        return
            LPMath.DistributeExcessIdleParams({
                presentValueParams: presentValueParams,
                startingPresentValue: startingPresentValue,
                activeLpTotalSupply: hyperdrive.totalSupply(
                    AssetId._LP_ASSET_ID
                ),
                withdrawalSharesTotalSupply: hyperdrive.totalSupply(
                    AssetId._WITHDRAWAL_SHARE_ASSET_ID
                ) - poolInfo.withdrawalSharesReadyToWithdraw,
                idle: uint256(hyperdrive.solvency()),
                netCurveTrade: netCurveTrade,
                originalShareReserves: presentValueParams.shareReserves,
                originalShareAdjustment: presentValueParams.shareAdjustment,
                originalBondReserves: presentValueParams.bondReserves
            });
    }

    function presentValue(
        IHyperdrive hyperdrive
    ) internal view returns (uint256) {
        return
            LPMath
                .calculatePresentValue(hyperdrive.getPresentValueParams())
                .mulDown(hyperdrive.getPoolInfo().vaultSharePrice);
    }

    function lpSharePrice(
        IHyperdrive hyperdrive
    ) internal view returns (uint256) {
        return hyperdrive.presentValue().divDown(hyperdrive.lpTotalSupply());
    }

    function lpTotalSupply(
        IHyperdrive hyperdrive
    ) internal view returns (uint256) {
        return
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID) +
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID) -
            hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw;
    }

    function idle(IHyperdrive hyperdrive) internal view returns (uint256) {
        return
            uint256(hyperdrive.solvency().max(0)).mulDown(
                hyperdrive.getPoolInfo().vaultSharePrice
            );
    }

    function solvency(IHyperdrive hyperdrive) internal view returns (int256) {
        IHyperdrive.PoolConfig memory config = hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
        return
            int256(info.shareReserves) -
            int256(info.longExposure.divDown(info.vaultSharePrice)) -
            int256(config.minimumShareReserves);
    }

    function k(IHyperdrive hyperdrive) internal view returns (uint256) {
        IHyperdrive.PoolConfig memory config = hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
        return
            YieldSpaceMath.kDown(
                HyperdriveMath.calculateEffectiveShareReserves(
                    info.shareReserves,
                    info.shareAdjustment
                ),
                info.bondReserves,
                ONE - config.timeStretch,
                info.vaultSharePrice,
                config.initialVaultSharePrice
            );
    }
}
