/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Errors } from "./Errors.sol";
import { FixedPointMath } from "./FixedPointMath.sol";
import { YieldSpaceMath } from "./YieldSpaceMath.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

/// @author Delve
/// @title Hyperdrive
/// @notice Math for the Hyperdrive pricing model.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library HyperdriveMath {
    using FixedPointMath for uint256;

    /// @dev Calculates the spot price without slippage of bonds in terms of shares.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _initialSharePrice The initial share price as an 18 fixed-point value.
    /// @param _normalizedTimeRemaining The normalized amount of time remaining until maturity.
    /// @param _timeStretch The time stretch parameter as an 18 fixed-point value.
    /// @return spotPrice The spot price of bonds in terms of shares as an 18 fixed-point value.
    function calculateSpotPrice(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _initialSharePrice,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch
    ) internal pure returns (uint256 spotPrice) {
        // (y / (mu * z)) ** -tau
        // ((mu * z) / y) ** tau
        uint256 tau = _normalizedTimeRemaining.mulDown(_timeStretch);

        spotPrice = _initialSharePrice
            .mulDivDown(_shareReserves, _bondReserves)
            .pow(tau);
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
            // full time remaining of position
            FixedPointMath.ONE_18,
            _timeStretch
        );

        // r = (1 - p) / (p * t)
        return
            FixedPointMath.ONE_18.sub(spotPrice).divDown(
                spotPrice.mulDown(annualizedTime)
            );
    }

    /// @dev Calculates the initial bond reserves assuming that the initial LP
    ///      receives LP shares amounting to c * z + y. Throughout the rest of
    ///      the codebase, the bond reserves used include the LP share
    ///      adjustment specified in YieldSpace. The bond reserves returned by
    ///      this function are unadjusted which makes it easier to calculate the
    ///      initial LP shares.
    /// @param _shareReserves The pool's share reserves.
    /// @param _sharePrice The pool's share price.
    /// @param _initialSharePrice The pool's initial share price.
    /// @param _apr The pool's APR.
    /// @param _positionDuration The amount of time until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @return bondReserves The bond reserves (without adjustment) that make
    ///         the pool have a specified APR.
    function calculateInitialBondReserves(
        uint256 _shareReserves,
        uint256 _sharePrice,
        uint256 _initialSharePrice,
        uint256 _apr,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 bondReserves) {
        // NOTE: Using divDown to convert to fixed point format.
        uint256 t = _positionDuration.divDown(365 days);
        uint256 tau = FixedPointMath.ONE_18.mulDown(_timeStretch);
        // mu * (1 + apr * t) ** (1 / tau) - c
        uint256 rhs = _initialSharePrice
            .mulDown(
                FixedPointMath.ONE_18.add(_apr.mulDown(t)).pow(
                    FixedPointMath.ONE_18.divUp(tau)
                )
            )
            .sub(_sharePrice);
        // (z / 2) * (mu * (1 + apr * t) ** (1 / tau) - c)
        return _shareReserves.divDown(2 * FixedPointMath.ONE_18).mulDown(rhs);
    }

    struct OpenLongCalculationParams {
        uint256 shareAmount;
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 sharePrice;
        uint256 normalizedTimeRemaining;
        uint256 initialSharePrice;
        uint256 timeStretch;
        uint256 curveFee;
        uint256 flatFee;
        uint256 governanceFee;
    }

    /// @notice Calculates the openShort trade deltas, fees and proceeds
    /// @param _params Parameters needed to calculate the openShort trade
    /// @return shareReservesDelta The change in the pools share reserves
    /// @return bondReservesDelta The change in the pools bond reserves
    /// @return totalGovernanceFee The portion of fees given to governance for
    ///                            this trade
    /// @return bondProceeds The amount of bonds the user will receive
    function calculateOpenLong(
        OpenLongCalculationParams memory _params
    )
        internal
        pure
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 totalGovernanceFee,
            uint256 bondProceeds
        )
    {
        // Calculate the effect that opening the long should have on the pool's
        // reserves as well as the amount of bond the trader receives.
        (
            shareReservesDelta,
            bondReservesDelta,
            bondProceeds
        ) = calculateOpenLongTrade(
            _params.shareReserves,
            _params.bondReserves,
            _params.shareAmount,
            _params.normalizedTimeRemaining,
            _params.timeStretch,
            _params.sharePrice,
            _params.initialSharePrice
        );

        // Calculate the spot price of bonds in terms of shares.
        uint256 spotPrice = calculateSpotPrice(
            _params.shareReserves,
            _params.bondReserves,
            _params.initialSharePrice,
            _params.normalizedTimeRemaining,
            _params.timeStretch
        );

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of bonds received given shares in, we
        // subtract the fee from the bond deltas so that the trader receives
        // less bonds.
        FeeDeltas memory feeDeltas = calculateFeesOutGivenSharesIn(
            _params.shareAmount,
            bondProceeds,
            _params.normalizedTimeRemaining,
            spotPrice,
            _params.sharePrice,
            _params.curveFee,
            _params.flatFee,
            _params.governanceFee
        );

        // Apply the fee deltas
        bondReservesDelta -= (feeDeltas.totalCurveFee -
            feeDeltas.governanceCurveFee);
        bondProceeds -= feeDeltas.totalCurveFee + feeDeltas.totalFlatFee;
        shareReservesDelta -= feeDeltas.governanceCurveFee.divDown(
            _params.sharePrice
        );
        totalGovernanceFee = (feeDeltas.governanceCurveFee +
            feeDeltas.governanceFlatFee).divDown(_params.sharePrice);

        return (
            shareReservesDelta,
            bondReservesDelta,
            totalGovernanceFee,
            bondProceeds
        );
    }

    /// @dev Calculates the number of bonds a user will receive when opening a long position.
    /// @param _shareReserves The pool's share reserves.
    /// @param _bondReserves The pool's bond reserves.
    /// @param _amountIn The amount of shares the user is depositing.
    /// @param _normalizedTimeRemaining The amount of time remaining until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return shareReservesDelta The shares paid to the reserves in the trade.
    /// @return bondReservesDelta The bonds paid by the reserves in the trade.
    /// @return bondProceeds The bonds that the user will receive.
    function calculateOpenLongTrade(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
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
            uint256 bondProceeds
        )
    {
        // Calculate the flat part of the trade.
        bondProceeds = _amountIn.mulDown(
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining)
        );
        shareReservesDelta = _amountIn.mulDown(_normalizedTimeRemaining);
        // (time remaining)/(term length) is always 1 so we just use _timeStretch
        bondReservesDelta = YieldSpaceMath.calculateBondsOutGivenSharesIn(
            _shareReserves,
            _bondReserves,
            shareReservesDelta,
            FixedPointMath.ONE_18.sub(_timeStretch),
            _sharePrice,
            _initialSharePrice
        );
        bondProceeds += bondReservesDelta;
        return (shareReservesDelta, bondReservesDelta, bondProceeds);
    }

    struct CloseLongCalculationParams {
        uint256 bondAmount;
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 sharePrice;
        uint256 closeSharePrice;
        uint256 initialSharePrice;
        uint256 normalizedTimeRemaining;
        uint256 timeStretch;
        uint256 curveFee;
        uint256 flatFee;
        uint256 governanceFee;
    }

    /// @notice Calculates the closeLong trade deltas, fees and proceeds
    /// @param _params Parameters needed to calculate the openShort trade
    /// @return shareReservesDelta The change in the pools share reserves
    /// @return bondReservesDelta The change in the pools bond reserves
    /// @return totalGovernanceFee The portion of fees given to governance for
    ///                            this trade
    /// @return shareProceeds The amount of shares the user will receive
    function calculateCloseLong(
        CloseLongCalculationParams memory _params
    )
        internal
        pure
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 totalGovernanceFee,
            uint256 shareProceeds
        )
    {
        // Calculate the effect that closing the long should have on the pool's
        // reserves as well as the amount of shares the trader receives for
        // selling the bonds at the market price.
        (
            shareReservesDelta,
            bondReservesDelta,
            shareProceeds
        ) = calculateCloseLongTrade(
            _params.shareReserves,
            _params.bondReserves,
            _params.bondAmount,
            _params.normalizedTimeRemaining,
            _params.timeStretch,
            _params.closeSharePrice,
            _params.sharePrice,
            _params.initialSharePrice
        );

        // Calculate the spot price of bonds in terms of shares.
        uint256 spotPrice = calculateSpotPrice(
            _params.shareReserves,
            _params.bondReserves,
            _params.initialSharePrice,
            _params.normalizedTimeRemaining,
            _params.timeStretch
        );

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of shares received given bonds in, we
        // subtract the fee from the share deltas so that the trader receives
        // less shares.
        HyperdriveMath.FeeDeltas
            memory feeDeltas = calculateFeesOutGivenBondsIn(
                _params.bondAmount,
                _params.normalizedTimeRemaining,
                spotPrice,
                _params.sharePrice,
                _params.curveFee,
                _params.flatFee,
                _params.governanceFee
            );

        // Apply the fee deltas
        shareReservesDelta -= feeDeltas.totalCurveFee;
        shareProceeds -= feeDeltas.totalCurveFee + feeDeltas.totalFlatFee;
        totalGovernanceFee = (feeDeltas.governanceCurveFee +
            feeDeltas.governanceFlatFee);

        return (
            shareReservesDelta,
            bondReservesDelta,
            totalGovernanceFee,
            shareProceeds
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
    /// @param _closeSharePrice The share price at close.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return shareReservesDelta The shares paid by the reserves in the trade.
    /// @return bondReservesDelta The bonds paid to the reserves in the trade.
    /// @return shareProceeds The shares that the user will receive.
    function calculateCloseLongTrade(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _timeStretch,
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
        shareProceeds = _amountIn
            .mulDown(FixedPointMath.ONE_18.sub(_normalizedTimeRemaining))
            .divDown(_sharePrice);

        // TODO: We need better testing for this. This may be correct but the
        // intuition that longs only take a loss on the flat component of their
        // trade feels a bit handwavy because negative interest accrued on the
        // entire trade amount.
        //
        // If there's net negative interest over the period, the flat portion of
        // the trade is reduced in proportion to the negative interest. We
        // always attribute negative interest to the long since it's difficult
        // or impossible to attribute the negative interest to the short in
        // practice.
        if (_initialSharePrice > _closeSharePrice) {
            shareProceeds = (shareProceeds.mulUp(_closeSharePrice)).divDown(
                _initialSharePrice
            );
        }

        if (_normalizedTimeRemaining > 0) {
            // Calculate the curved part of the trade.
            bondReservesDelta = _amountIn.mulDown(_normalizedTimeRemaining);
            // (time remaining)/(term length) is always 1 so we just use _timeStretch
            shareReservesDelta = YieldSpaceMath.calculateSharesOutGivenBondsIn(
                _shareReserves,
                _bondReserves,
                bondReservesDelta,
                FixedPointMath.ONE_18.sub(_timeStretch),
                _sharePrice,
                _initialSharePrice
            );
            shareProceeds += shareReservesDelta;
        }
        return (shareReservesDelta, bondReservesDelta, shareProceeds);
    }

    struct OpenShortCalculationParams {
        uint256 bondAmount;
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 sharePrice;
        uint256 openSharePrice;
        uint256 initialSharePrice;
        uint256 normalizedTimeRemaining;
        uint256 timeStretch;
        uint256 curveFee;
        uint256 flatFee;
        uint256 governanceFee;
    }

    /// @notice Calculates the openShort trade deltas, fees and proceeds
    /// @param _params Parameters needed to calculate the openShort trade
    /// @return shareReservesDelta The change in the pools share reserves
    /// @return bondReservesDelta The change in the pools bond reserves
    /// @return totalGovernanceFee The portion of fees given to governance for
    ///                            this trade
    /// @return baseToDeposit The amount of base the user must pay for the short
    /// @return shareProceeds The proceeds of the short the user will receive
    function calculateOpenShort(
        OpenShortCalculationParams memory _params
    )
        internal
        pure
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 totalGovernanceFee,
            uint256 baseToDeposit,
            uint256 shareProceeds
        )
    {
        // Calculate the effect that opening the short should have on the pool's
        // reserves as well as the amount of shares the trader receives from
        // selling the shorted bonds at the market price.
        (
            shareReservesDelta,
            bondReservesDelta,
            shareProceeds
        ) = calculateOpenShortTrade(
            _params.shareReserves,
            _params.bondReserves,
            _params.bondAmount,
            _params.normalizedTimeRemaining,
            _params.timeStretch,
            _params.sharePrice,
            _params.initialSharePrice
        );

        // If the base proceeds of selling the bonds is greater than the bond
        // amount, then the trade occurred in the negative interest domain. We
        // revert in these pathological cases.
        if (shareProceeds.mulDown(_params.sharePrice) > _params.bondAmount)
            revert Errors.NegativeInterest();

        // Calculate the spot price of bonds in terms of shares.
        uint256 spotPrice = calculateSpotPrice(
            _params.shareReserves,
            _params.bondReserves,
            _params.initialSharePrice,
            _params.normalizedTimeRemaining,
            _params.timeStretch
        );

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of shares received given bonds in, we
        // subtract the fee from the share deltas so that the trader receives
        // less shares.
        FeeDeltas memory feeDeltas = calculateFeesOutGivenBondsIn(
            _params.bondAmount,
            _params.normalizedTimeRemaining,
            spotPrice,
            _params.sharePrice,
            _params.curveFee,
            _params.flatFee,
            _params.governanceFee
        );

        // Attribute the fees to the share deltas.
        shareReservesDelta -= feeDeltas.totalCurveFee;
        shareProceeds -= feeDeltas.totalCurveFee + feeDeltas.totalFlatFee;
        totalGovernanceFee =
            feeDeltas.governanceCurveFee +
            feeDeltas.governanceFlatFee;

        // Calculate the amount of base the user must deposit.
        baseToDeposit = calculateShortProceeds(
            _params.bondAmount,
            shareProceeds,
            _params.openSharePrice,
            _params.sharePrice,
            _params.sharePrice
        ).mulDown(_params.sharePrice);

        return (
            shareReservesDelta,
            bondReservesDelta,
            totalGovernanceFee,
            baseToDeposit,
            shareProceeds
        );
    }

    /// @dev Calculates the amount of shares that will be received given a
    ///      specified amount of bonds.
    /// @param _shareReserves The pool's share reserves
    /// @param _bondReserves The pool's bonds reserves.
    /// @param _amountIn The amount of bonds the user is providing.
    /// @param _normalizedTimeRemaining The amount of time remaining until maturity in seconds.
    /// @param _timeStretch The time stretch parameter.
    /// @param _sharePrice The share price.
    /// @param _initialSharePrice The initial share price.
    /// @return shareReservesDelta The shares paid by the reserves in the trade.
    /// @return bondReservesDelta The bonds paid to the reserves in the trade.
    /// @return shareProceeds The shares that the user will receive.
    function calculateOpenShortTrade(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _amountIn,
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
            uint256 shareProceeds
        )
    {
        // Calculate the flat part of the trade.
        shareProceeds = _amountIn
            .mulDown(FixedPointMath.ONE_18.sub(_normalizedTimeRemaining))
            .divDown(_sharePrice);
        // Calculate the curved part of the trade.
        bondReservesDelta = _amountIn.mulDown(_normalizedTimeRemaining);
        // (time remaining)/(term length) is always 1 so we just use _timeStretch
        shareReservesDelta = YieldSpaceMath.calculateSharesOutGivenBondsIn(
            _shareReserves,
            _bondReserves,
            bondReservesDelta,
            FixedPointMath.ONE_18.sub(_timeStretch),
            _sharePrice,
            _initialSharePrice
        );
        shareProceeds += shareReservesDelta;
        return (shareReservesDelta, bondReservesDelta, shareProceeds);
    }

    struct CloseShortCalculationParams {
        uint256 bondAmount;
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 openSharePrice;
        uint256 sharePrice;
        uint256 closeSharePrice;
        uint256 initialSharePrice;
        uint256 normalizedTimeRemaining;
        uint256 timeStretch;
        uint256 curveFee;
        uint256 flatFee;
        uint256 governanceFee;
    }

    /// @notice Calculates the closeShort trade deltas, fees and proceeds
    /// @param _params Parameters needed to calculate the closeShort trade
    /// @return shareReservesDelta The change in the pools share reserves
    /// @return bondReservesDelta The change in the pools bond reserves
    /// @return totalGovernanceFee The portion of fees given to governance for
    ///                            this trade
    /// @return sharePayment The shares that the user must pay for the short
    /// @return shareProceeds The proceeds of the short the user will receive
    function calculateCloseShort(
        CloseShortCalculationParams memory _params
    )
        internal
        pure
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 totalGovernanceFee,
            uint256 sharePayment,
            uint256 shareProceeds
        )
    {
        // Calculate the effect that closing the short should have on the pool's
        // reserves as well as the amount of shares the trader receives from
        // selling the shorted bonds
        (
            shareReservesDelta,
            bondReservesDelta,
            sharePayment
        ) = calculateCloseShortTrade(
            _params.shareReserves,
            _params.bondReserves,
            _params.bondAmount,
            _params.normalizedTimeRemaining,
            _params.timeStretch,
            _params.sharePrice,
            _params.initialSharePrice
        );

        // Calculate the spot price of bonds in terms of shares.
        uint256 spotPrice = calculateSpotPrice(
            _params.shareReserves,
            _params.bondReserves,
            _params.initialSharePrice,
            _params.normalizedTimeRemaining,
            _params.timeStretch
        );

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of shares paid given bonds out, we add
        // the fee from the share deltas so that the trader pays less shares.
        FeeDeltas memory feeDeltas = calculateFeesInGivenBondsOut(
            _params.bondAmount,
            _params.normalizedTimeRemaining,
            spotPrice,
            _params.sharePrice,
            _params.curveFee,
            _params.flatFee,
            _params.governanceFee
        );
        shareReservesDelta += (feeDeltas.totalCurveFee -
            feeDeltas.governanceCurveFee);
        sharePayment += feeDeltas.totalCurveFee + feeDeltas.totalFlatFee;

        // Derive the total amount of fees given to governance
        totalGovernanceFee =
            feeDeltas.governanceCurveFee +
            feeDeltas.governanceFlatFee;

        // Calculates the proceeds of the trade
        shareProceeds = calculateShortProceeds(
            _params.bondAmount,
            sharePayment,
            _params.openSharePrice,
            _params.closeSharePrice,
            _params.sharePrice
        );

        return (
            shareReservesDelta,
            bondReservesDelta,
            totalGovernanceFee,
            sharePayment,
            shareProceeds
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
    function calculateCloseShortTrade(
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
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining),
            _sharePrice
        );

        if (_normalizedTimeRemaining > 0) {
            bondReservesDelta = _amountOut.mulDown(_normalizedTimeRemaining);
            shareReservesDelta = YieldSpaceMath.calculateSharesInGivenBondsOut(
                _shareReserves,
                _bondReserves,
                bondReservesDelta,
                FixedPointMath.ONE_18.sub(_timeStretch),
                _sharePrice,
                _initialSharePrice
            );
            sharePayment += shareReservesDelta;
        }

        return (shareReservesDelta, bondReservesDelta, sharePayment);
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
    /// @return shareProceeds The short proceeds in shares.
    function calculateShortProceeds(
        uint256 _bondAmount,
        uint256 _shareAmount,
        uint256 _openSharePrice,
        uint256 _closeSharePrice,
        uint256 _sharePrice
    ) internal pure returns (uint256 shareProceeds) {
        // If the interest is more negative than the trading profits and margin
        // released, than the short proceeds are marked to zero. Otherwise, we
        // calculate the proceeds as the sum of the trading proceeds, the
        // interest proceeds, and the margin released.
        uint256 bondFactor = _bondAmount.mulDivDown(
            _closeSharePrice,
            _openSharePrice.mulDown(_sharePrice)
        );
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
                _openSharePrice.mulDown(_sharePrice)
            );
        }
        return shareInterest;
    }

    /// @dev Calculates the base volume of an open trade given the base amount,
    ///      the bond amount, and the time remaining. Since the base amount
    ///      takes into account backdating, we can't use this as our base
    ///      volume. Since we linearly interpolate between the base volume
    ///      and the bond amount as the time remaining goes from 1 to 0, the
    ///      base volume is can be determined as follows:
    ///
    ///      baseAmount = t * baseVolume + (1 - t) * bondAmount
    ///                               =>
    ///      baseVolume = (baseAmount - (1 - t) * bondAmount) / t
    /// @param _baseAmount The base exchanged in the open trade.
    /// @param _bondAmount The bonds exchanged in the open trade.
    /// @param _timeRemaining The time remaining in the position.
    /// @return baseVolume The calculated base volume.
    function calculateBaseVolume(
        uint256 _baseAmount,
        uint256 _bondAmount,
        uint256 _timeRemaining
    ) internal pure returns (uint256 baseVolume) {
        // If the time remaining is 0, the position has already matured and
        // doesn't have an impact on LP's ability to withdraw. This is a
        // pathological case that should never arise.
        if (_timeRemaining == 0) return 0;
        baseVolume = (
            _baseAmount.sub(
                (FixedPointMath.ONE_18.sub(_timeRemaining)).mulDown(_bondAmount)
            )
        ).divDown(_timeRemaining);
    }

    /// @dev Computes the LP allocation adjustment for a position. This is used
    ///      to accurately account for the duration risk that LPs take on when
    ///      adding liquidity so that LP shares can be rewarded fairly.
    /// @param _positionsOutstanding The position balance outstanding.
    /// @param _baseVolume The base volume created by opening the positions.
    /// @param _averageTimeRemaining The average time remaining of the positions.
    /// @param _sharePrice The pool's share price.
    /// @return adjustment The allocation adjustment.
    function calculateLpAllocationAdjustment(
        uint256 _positionsOutstanding,
        uint256 _baseVolume,
        uint256 _averageTimeRemaining,
        uint256 _sharePrice
    ) internal pure returns (uint256 adjustment) {
        // baseAdjustment = t * _baseVolume + (1 - t) * _positionsOutstanding
        adjustment = (_averageTimeRemaining.mulDown(_baseVolume)).add(
            (FixedPointMath.ONE_18.sub(_averageTimeRemaining)).mulDown(
                _positionsOutstanding
            )
        );
        // adjustment = baseAdjustment / c
        adjustment = adjustment.divDown(_sharePrice);
    }

    /// @dev Calculates the amount of base shares released from burning a
    ///      a specified amount of LP shares from the pool.
    /// @param _shares The amount of LP shares burned from the pool.
    /// @param _shareReserves The pool's share reserves.
    /// @param _lpTotalSupply The pool's total supply of LP shares.
    /// @param _longsOutstanding The amount of longs that haven't been closed.
    /// @param _shortsOutstanding The amount of shorts that haven't been closed.
    /// @param _sharePrice The pool's share price.
    /// @return shares The amount of base shares released.
    /// @return longWithdrawalShares The amount of long withdrawal shares
    ///         received.
    /// @return shortWithdrawalShares The amount of short withdrawal shares
    ///         received.
    function calculateOutForLpSharesIn(
        uint256 _shares,
        uint256 _shareReserves,
        uint256 _lpTotalSupply,
        uint256 _longsOutstanding,
        uint256 _shortsOutstanding,
        uint256 _sharePrice
    )
        internal
        pure
        returns (
            uint256 shares,
            uint256 longWithdrawalShares,
            uint256 shortWithdrawalShares
        )
    {
        // dl / l
        uint256 poolFactor = _shares.divDown(_lpTotalSupply);
        // (z - o_l / c) * (dl / l)
        shares = _shareReserves
            .sub(_longsOutstanding.divDown(_sharePrice))
            .mulDown(poolFactor);
        // longsOutstanding * (dl / l)
        longWithdrawalShares = _longsOutstanding.mulDown(poolFactor);
        // shortsOutstanding * (dl / l)
        shortWithdrawalShares = _shortsOutstanding.mulDown(poolFactor);
        return (shares, longWithdrawalShares, shortWithdrawalShares);
    }

    struct FeeDeltas {
        uint256 totalCurveFee;
        uint256 totalFlatFee;
        uint256 governanceCurveFee;
        uint256 governanceFlatFee;
    }

    /// @dev Calculates the fees for the flat and curve portion of calcOutGivenIn
    /// @param _bondAmount The amount of bonds to short
    /// @param _normalizedTimeRemaining The normalized amount of time until maturity
    /// @param _spotPrice The spot price of the pool
    /// @param _sharePrice The current price of shares in terms of base
    /// @param _curveFee The percentage fee to be applied for the curve part of the trade equation
    /// @param _flatFee The percentage fee to be applied for the flat part of the trade equation
    /// @param _governanceFee The percentage amount of the total fees to be given to governance
    /// @return The fee deltas
    function calculateFeesOutGivenBondsIn(
        uint256 _bondAmount,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice,
        uint256 _curveFee,
        uint256 _flatFee,
        uint256 _governanceFee
    ) internal pure returns (FeeDeltas memory) {
        // curve fee = ((1 - p) * phi_curve * d_y * t) / c
        uint256 curve = (FixedPointMath.ONE_18.sub(_spotPrice));
        uint256 totalCurveFee = curve
            .mulDown(_curveFee)
            .mulDown(_bondAmount)
            .mulDivDown(_normalizedTimeRemaining, _sharePrice);

        // flat fee = (d_y * (1 - t) * phi_flat) / c
        uint256 flat = _bondAmount.mulDivDown(
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining),
            _sharePrice
        );
        uint256 totalFlatFee = (flat.mulDown(_flatFee));

        // calculate the curve portion of the gov fee
        uint256 governanceCurveFee = totalCurveFee.mulDown(_governanceFee);
        // calculate the flat portion of the gov fee
        uint256 governanceFlatFee = totalFlatFee.mulDown(_governanceFee);

        return
            FeeDeltas({
                totalCurveFee: totalCurveFee,
                totalFlatFee: totalFlatFee,
                governanceCurveFee: governanceCurveFee,
                governanceFlatFee: governanceFlatFee
            });
    }

    /// @dev Calculates the fees for the curve portion of hyperdrive calcInGivenOut
    /// @param _bondAmount The given bond amount out.
    /// @param _normalizedTimeRemaining The normalized amount of time until maturity.
    /// @param _spotPrice The price without slippage of bonds in terms of shares.
    /// @param _sharePrice The current price of shares in terms of base.
    /// @param _curveFee The percentage fee to be applied for the curve part of the trade equation
    /// @param _flatFee The percentage fee to be applied for the flat part of the trade equation
    /// @param _governanceFee The percentage amount of the total fees to be given to governance
    /// @return The fee deltas
    function calculateFeesInGivenBondsOut(
        uint256 _bondAmount,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice,
        uint256 _curveFee,
        uint256 _flatFee,
        uint256 _governanceFee
    ) internal pure returns (FeeDeltas memory) {
        uint256 curve = _bondAmount.mulDown(_normalizedTimeRemaining);
        // curve fee = ((1 - p) * d_y * t * phi_curve)/c
        uint256 totalCurveFee = FixedPointMath.ONE_18.sub(_spotPrice);
        totalCurveFee = totalCurveFee
            .mulDown(_curveFee)
            .mulDown(curve)
            .mulDivDown(_normalizedTimeRemaining, _sharePrice);
        // calculate the curve portion of the governance fee
        uint256 governanceCurveFee = totalCurveFee.mulDown(_governanceFee);
        // flat fee = (d_y * (1 - t) * phi_flat)/c
        uint256 flat = _bondAmount.mulDivDown(
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining),
            _sharePrice
        );
        uint256 totalFlatFee = (flat.mulDown(_flatFee));
        // calculate the flat portion of the governance fee
        uint256 governanceFlatFee = totalFlatFee.mulDown(_governanceFee);

        return
            FeeDeltas({
                totalCurveFee: totalCurveFee,
                totalFlatFee: totalFlatFee,
                governanceCurveFee: governanceCurveFee,
                governanceFlatFee: governanceFlatFee
            });
    }

    /// @dev Calculates the fees for the flat and curve portion of hyperdrive calcOutGivenIn
    /// @param _shareAmount The amount of shares in.
    /// @param _bondAmount The amount of bonds out before fees are applied.
    /// @param _normalizedTimeRemaining The normalized amount of time until maturity.
    /// @param _spotPrice The price without slippage of bonds in terms of shares.
    /// @param _sharePrice The current price of shares in terms of base.
    /// @param _curveFee The percentage fee to be applied for the curve part of the trade equation
    /// @param _flatFee The percentage fee to be applied for the flat part of the trade equation
    /// @param _governanceFee The percentage amount of the total fees to be given to governance
    /// @return The fee deltas
    function calculateFeesOutGivenSharesIn(
        uint256 _shareAmount,
        uint256 _bondAmount,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice,
        uint256 _curveFee,
        uint256 _flatFee,
        uint256 _governanceFee
    ) internal pure returns (FeeDeltas memory) {
        // curve fee = ((1 / p) - 1) * phi_curve * c * d_z * t
        uint256 totalCurveFee = (FixedPointMath.ONE_18.divDown(_spotPrice)).sub(
            FixedPointMath.ONE_18
        );
        totalCurveFee = totalCurveFee
            .mulDown(_curveFee)
            .mulDown(_sharePrice)
            .mulDown(_shareAmount)
            .mulDown(_normalizedTimeRemaining);

        // flat fee = c * d_z * (1 - t) * phi_flat
        uint256 totalFlatFee = _shareAmount.mulDown(
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining)
        );
        totalFlatFee = totalFlatFee.mulDown(_sharePrice).mulDown(_flatFee);

        // governanceCurveFee = d_z * (curve_fee / d_y) * c * phi_gov
        uint256 governanceCurveFee = _shareAmount.mulDivDown(
            totalCurveFee,
            _bondAmount
        );
        governanceCurveFee = governanceCurveFee.mulDown(_sharePrice).mulDown(
            _governanceFee
        );

        // calculate the flat portion of the governance fee
        uint256 governanceFlatFee = totalFlatFee.mulDown(_governanceFee);

        return
            FeeDeltas({
                totalCurveFee: totalCurveFee,
                totalFlatFee: totalFlatFee,
                governanceCurveFee: governanceCurveFee,
                governanceFlatFee: governanceFlatFee
            });
    }
}
