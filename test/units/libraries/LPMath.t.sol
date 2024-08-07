// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { LPMath } from "../../../contracts/src/libraries/LPMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "../../../contracts/src/libraries/YieldSpaceMath.sol";
import { MockLPMath } from "../../../contracts/test/MockLPMath.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract LPMathTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;
    using LPMath for *;

    function test__calculateInitialReserves() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockLPMath lpMath = new MockLPMath();

        // Test .1% APR
        uint256 shareReserves = 500_000_000e18;
        uint256 initialVaultSharePrice = 0.5e18;
        uint256 vaultSharePrice = 2.5e18;
        uint256 apr = 0.001e18;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = HyperdriveMath.calculateTimeStretch(
            0.001e18,
            positionDuration
        );
        (, int256 shareAdjustment, uint256 bondReserves) = lpMath
            .calculateInitialReserves(
                shareReserves,
                vaultSharePrice,
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
        uint256 effectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(shareReserves, shareAdjustment);
        uint256 result = HyperdriveMath.calculateSpotAPR(
            effectiveShareReserves,
            bondReserves,
            initialVaultSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 20);

        // Test 1% APR
        apr = 0.01e18;
        timeStretch = HyperdriveMath.calculateTimeStretch(
            0.01e18,
            positionDuration
        );
        (, shareAdjustment, bondReserves) = lpMath.calculateInitialReserves(
            shareReserves,
            vaultSharePrice,
            initialVaultSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        effectiveShareReserves = HyperdriveMath.calculateEffectiveShareReserves(
            shareReserves,
            shareAdjustment
        );
        result = HyperdriveMath.calculateSpotAPR(
            effectiveShareReserves,
            bondReserves,
            initialVaultSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 1);

        // Test 5% APR
        apr = 0.05e18;
        timeStretch = HyperdriveMath.calculateTimeStretch(
            0.05e18,
            positionDuration
        );
        (, shareAdjustment, bondReserves) = lpMath.calculateInitialReserves(
            shareReserves,
            vaultSharePrice,
            initialVaultSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        effectiveShareReserves = HyperdriveMath.calculateEffectiveShareReserves(
            shareReserves,
            shareAdjustment
        );
        result = HyperdriveMath.calculateSpotAPR(
            effectiveShareReserves,
            bondReserves,
            initialVaultSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 1);

        // Test 25% APR
        apr = 0.25e18;
        timeStretch = HyperdriveMath.calculateTimeStretch(
            0.25e18,
            positionDuration
        );
        (, shareAdjustment, bondReserves) = lpMath.calculateInitialReserves(
            shareReserves,
            vaultSharePrice,
            initialVaultSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        effectiveShareReserves = HyperdriveMath.calculateEffectiveShareReserves(
            shareReserves,
            shareAdjustment
        );
        result = HyperdriveMath.calculateSpotAPR(
            effectiveShareReserves,
            bondReserves,
            initialVaultSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 1);

        // Test 50% APR
        apr = 0.5e18;
        timeStretch = HyperdriveMath.calculateTimeStretch(
            0.5e18,
            positionDuration
        );
        (, shareAdjustment, bondReserves) = lpMath.calculateInitialReserves(
            shareReserves,
            vaultSharePrice,
            initialVaultSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        effectiveShareReserves = HyperdriveMath.calculateEffectiveShareReserves(
            shareReserves,
            shareAdjustment
        );
        result = HyperdriveMath.calculateSpotAPR(
            effectiveShareReserves,
            bondReserves,
            initialVaultSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 1);

        // Test 100% APR
        apr = 1e18;
        timeStretch = HyperdriveMath.calculateTimeStretch(
            1e18,
            positionDuration
        );
        (, shareAdjustment, bondReserves) = lpMath.calculateInitialReserves(
            shareReserves,
            vaultSharePrice,
            initialVaultSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        effectiveShareReserves = HyperdriveMath.calculateEffectiveShareReserves(
            shareReserves,
            shareAdjustment
        );
        result = HyperdriveMath.calculateSpotAPR(
            effectiveShareReserves,
            bondReserves,
            initialVaultSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 4);
    }

    function test__calculatePresentValue() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockLPMath lpMath = new MockLPMath();

        uint256 apr = 0.02e18;
        uint256 initialVaultSharePrice = 1e18;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = HyperdriveMath.calculateTimeStretch(
            apr,
            positionDuration
        );

        // no open positions.
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialVaultSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: 1e18,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // all longs on the curve.
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialVaultSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 1e18,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);
            params.shareReserves -= YieldSpaceMath
                .calculateSharesOutGivenBondsInDown(
                    params.shareReserves,
                    params.bondReserves,
                    params.longsOutstanding,
                    ONE - params.timeStretch,
                    params.vaultSharePrice,
                    params.initialVaultSharePrice
                );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // all longs on the flat.
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialVaultSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);
            params.shareReserves -= params.longsOutstanding.divDown(
                params.vaultSharePrice
            );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // all shorts on the curve.
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialVaultSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 1e18
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);
            params.shareReserves += YieldSpaceMath
                .calculateSharesInGivenBondsOutUp(
                    params.shareReserves,
                    params.bondReserves,
                    params.shortsOutstanding,
                    ONE - params.timeStretch,
                    params.vaultSharePrice,
                    params.initialVaultSharePrice
                );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // all shorts on the flat.
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialVaultSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);
            params.shareReserves += params.shortsOutstanding.divDown(
                params.vaultSharePrice
            );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // longs and shorts completely net.
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialVaultSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 0.3e18,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0.3e18
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // all shorts on the curve, all longs on the flat.
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialVaultSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 1e18
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);
            params.shareReserves += YieldSpaceMath
                .calculateSharesInGivenBondsOutUp(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    params.shortsOutstanding,
                    ONE - params.timeStretch,
                    params.vaultSharePrice,
                    params.initialVaultSharePrice
                );
            params.shareReserves -= params.longsOutstanding.divDown(
                params.vaultSharePrice
            );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // all longs on the curve, all shorts on the flat.
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialVaultSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 1e18,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);
            params.shareReserves -= YieldSpaceMath
                .calculateSharesOutGivenBondsInDown(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    params.longsOutstanding,
                    ONE - params.timeStretch,
                    params.vaultSharePrice,
                    params.initialVaultSharePrice
                );
            params.shareReserves += params.shortsOutstanding.divDown(
                params.vaultSharePrice
            );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // small amount of longs, large amount of shorts
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialVaultSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 100_000e18,
                    longAverageTimeRemaining: 0.75e18,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0.25e18
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);

            // net curve short and net flat short
            params.shareReserves += YieldSpaceMath
                .calculateSharesInGivenBondsOutUp(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    params.shortsOutstanding.mulDown(
                        params.shortAverageTimeRemaining
                    ) -
                        params.longsOutstanding.mulDown(
                            params.longAverageTimeRemaining
                        ),
                    ONE - params.timeStretch,
                    params.vaultSharePrice,
                    params.initialVaultSharePrice
                );
            params.shareReserves +=
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.vaultSharePrice
                ) -
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.vaultSharePrice
                );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // large amount of longs, small amount of shorts
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialVaultSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 0.75e18,
                    shortsOutstanding: 100_000e18,
                    shortAverageTimeRemaining: 0.25e18
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);

            // net curve long and net flat long
            params.shareReserves -= YieldSpaceMath
                .calculateSharesOutGivenBondsInDown(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    params.longsOutstanding.mulDown(
                        params.longAverageTimeRemaining
                    ) -
                        params.shortsOutstanding.mulDown(
                            params.shortAverageTimeRemaining
                        ),
                    ONE - params.timeStretch,
                    params.vaultSharePrice,
                    params.initialVaultSharePrice
                );
            params.shareReserves -=
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.vaultSharePrice
                ) -
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.vaultSharePrice
                );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // small amount of longs, large amount of shorts, no excess liquidity
        //
        // This scenario simulates all of the LPs losing their liquidity. What
        // is important is that the calculation won't fail in this scenario.
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 100_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        100_000e18,
                        initialVaultSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 100_000e18,
                    longAverageTimeRemaining: 0.75e18,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0.25e18
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);

            // Apply as much as possible to the curve and mark the rest of the
            // curve trade to a price of 1.
            uint256 netCurveTrade = params.shortsOutstanding.mulDown(
                params.shortAverageTimeRemaining
            ) -
                params.longsOutstanding.mulDown(
                    params.longAverageTimeRemaining
                );
            (uint256 maxCurveTrade, bool success) = YieldSpaceMath
                .calculateMaxBuyBondsOutSafe(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    ONE - params.timeStretch,
                    params.vaultSharePrice,
                    params.initialVaultSharePrice
                );
            assertEq(success, true);
            uint256 maxShareProceeds;
            (maxShareProceeds, success) = YieldSpaceMath
                .calculateMaxBuySharesInSafe(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    ONE - params.timeStretch,
                    params.vaultSharePrice,
                    params.initialVaultSharePrice
                );
            assertEq(success, true);
            params.shareReserves += maxShareProceeds;
            params.shareReserves += (netCurveTrade - maxCurveTrade).divDown(
                params.vaultSharePrice
            );

            // Apply the flat part to the reserves.
            params.shareReserves +=
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.vaultSharePrice
                ) -
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.vaultSharePrice
                );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // complicated scenario with non-trivial minimum share reserves
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 100_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        100_000e18,
                        initialVaultSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: 1e18,
                    minimumShareReserves: 1e18,
                    minimumTransactionAmount: 1e18,
                    timeStretch: timeStretch,
                    longsOutstanding: 100_000e18,
                    longAverageTimeRemaining: 0.75e18,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0.25e18
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);

            // Apply as much as possible to the curve and mark the rest of the
            // curve trade to a price of 1.
            uint256 netCurveTrade = params.shortsOutstanding.mulDown(
                params.shortAverageTimeRemaining
            ) -
                params.longsOutstanding.mulDown(
                    params.longAverageTimeRemaining
                );
            (uint256 maxCurveTrade, bool success) = YieldSpaceMath
                .calculateMaxBuyBondsOutSafe(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    ONE - params.timeStretch,
                    params.vaultSharePrice,
                    params.initialVaultSharePrice
                );
            assertEq(success, true);
            uint256 maxShareProceeds;
            (maxShareProceeds, success) = YieldSpaceMath
                .calculateMaxBuySharesInSafe(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    ONE - params.timeStretch,
                    params.vaultSharePrice,
                    params.initialVaultSharePrice
                );
            assertEq(success, true);
            params.shareReserves += maxShareProceeds;
            params.shareReserves += (netCurveTrade - maxCurveTrade).divDown(
                params.vaultSharePrice
            );

            // Apply the flat part to the reserves.
            params.shareReserves +=
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.vaultSharePrice
                ) -
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.vaultSharePrice
                );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // complicated scenario with non-trivial share adjustment
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 100_000e18,
                    shareAdjustment: 10_000e18,
                    bondReserves: calculateBondReserves(
                        100_000e18 - 10_000e18,
                        initialVaultSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: 1e18,
                    minimumShareReserves: 1e18,
                    minimumTransactionAmount: 1e18,
                    timeStretch: timeStretch,
                    longsOutstanding: 100_000e18,
                    longAverageTimeRemaining: 0.75e18,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0.25e18
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);

            // Apply as much as possible to the curve and mark the rest of the
            // curve trade to a price of 1.
            uint256 netCurveTrade = params.shortsOutstanding.mulDown(
                params.shortAverageTimeRemaining
            ) -
                params.longsOutstanding.mulDown(
                    params.longAverageTimeRemaining
                );
            (uint256 maxCurveTrade, bool success) = YieldSpaceMath
                .calculateMaxBuyBondsOutSafe(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    ONE - params.timeStretch,
                    params.vaultSharePrice,
                    params.initialVaultSharePrice
                );
            assertEq(success, true);
            uint256 maxShareProceeds;
            (maxShareProceeds, success) = YieldSpaceMath
                .calculateMaxBuySharesInSafe(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    ONE - params.timeStretch,
                    params.vaultSharePrice,
                    params.initialVaultSharePrice
                );
            assertEq(success, true);
            params.shareReserves += maxShareProceeds;
            params.shareReserves += (netCurveTrade - maxCurveTrade).divDown(
                params.vaultSharePrice
            );

            // Apply the flat part to the reserves.
            params.shareReserves +=
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.vaultSharePrice
                ) -
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.vaultSharePrice
                );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }
    }

    function test__calculateMaxShareReservesDelta() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockLPMath lpMath = new MockLPMath();

        uint256 apr = 0.02e18;
        uint256 initialVaultSharePrice = 0.5e18;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = HyperdriveMath.calculateTimeStretch(
            apr,
            positionDuration
        );

        // The pool is net neutral with no open positions.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: LPMath.calculatePresentValue(
                        presentValueParams
                    ),
                    activeLpTotalSupply: 0, // unused
                    withdrawalSharesTotalSupply: 0, // unused
                    idle: 10_000_000e18, // this is a fictional value for testing
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: shareReserves,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });
            (uint256 maxShareReservesDelta, bool success) = lpMath
                .calculateMaxShareReservesDeltaSafe(
                    params,
                    HyperdriveMath.calculateEffectiveShareReserves(
                        shareReserves,
                        shareAdjustment
                    )
                );
            assertEq(success, true);

            // The max share reserves delta is just the idle.
            assertEq(maxShareReservesDelta, params.idle);
        }

        // The pool is net neutral with open positions.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 0.5e18,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0.5e18
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: LPMath.calculatePresentValue(
                        presentValueParams
                    ),
                    activeLpTotalSupply: 0, // unused
                    withdrawalSharesTotalSupply: 0, // unused
                    idle: 10_000_000e18, // this is a fictional value for testing
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: shareReserves,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });
            (uint256 maxShareReservesDelta, bool success) = lpMath
                .calculateMaxShareReservesDeltaSafe(
                    params,
                    HyperdriveMath.calculateEffectiveShareReserves(
                        shareReserves,
                        shareAdjustment
                    )
                );
            assertEq(success, true);

            // The max share reserves delta is just the idle.
            assertEq(maxShareReservesDelta, params.idle);
        }

        // The pool is net long.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 0.5e18,
                    shortsOutstanding: 1_000_000e18,
                    shortAverageTimeRemaining: 0.5e18
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: LPMath.calculatePresentValue(
                        presentValueParams
                    ),
                    activeLpTotalSupply: 0, // unused
                    withdrawalSharesTotalSupply: 0, // unused
                    idle: 10_000_000e18, // this is a fictional value for testing
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: shareReserves,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });
            (uint256 maxShareReservesDelta, bool success) = lpMath
                .calculateMaxShareReservesDeltaSafe(
                    params,
                    HyperdriveMath.calculateEffectiveShareReserves(
                        shareReserves,
                        shareAdjustment
                    )
                );
            assertEq(success, true);

            // The max share reserves delta is just the idle.
            assertEq(maxShareReservesDelta, params.idle);
        }

        // The pool is net short but is not constrained by the maximum amount of
        // bonds that can be purchased.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 1_000_000e18,
                    longAverageTimeRemaining: 0.5e18,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0.5e18
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: LPMath.calculatePresentValue(
                        presentValueParams
                    ),
                    activeLpTotalSupply: 0, // unused
                    withdrawalSharesTotalSupply: 0, // unused
                    idle: 100e18, // this is a fictional value for testing
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: shareReserves,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });
            (uint256 maxShareReservesDelta, bool success) = lpMath
                .calculateMaxShareReservesDeltaSafe(
                    params,
                    HyperdriveMath.calculateEffectiveShareReserves(
                        shareReserves,
                        shareAdjustment
                    )
                );
            assertEq(success, true);

            // The max share reserves delta is just the idle.
            assertEq(maxShareReservesDelta, params.idle);
        }

        // The pool is net short and is constrained by the maximum amount of
        // bonds that can be purchased.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 50_000_000e18,
                    shortAverageTimeRemaining: 1e18
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: LPMath.calculatePresentValue(
                        presentValueParams
                    ),
                    activeLpTotalSupply: 0, // unused
                    withdrawalSharesTotalSupply: 0, // unused
                    idle: 80_000_000e18, // this is a fictional value for testing
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: shareReserves,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });
            (uint256 maxShareReservesDelta, bool success) = lpMath
                .calculateMaxShareReservesDeltaSafe(
                    params,
                    HyperdriveMath.calculateEffectiveShareReserves(
                        shareReserves,
                        shareAdjustment
                    )
                );
            assertEq(success, true);

            // The max share reserves delta should have been calculated so that
            // the maximum amount of bonds can be purchased is close to the net
            // curve trade.
            (
                params.presentValueParams.shareReserves,
                params.presentValueParams.shareAdjustment,
                params.presentValueParams.bondReserves
            ) = lpMath.calculateUpdateLiquidity(
                params.originalShareReserves,
                params.originalShareAdjustment,
                params.originalBondReserves,
                params.presentValueParams.minimumShareReserves,
                -int256(maxShareReservesDelta)
            );
            assertEq(success, true);
            uint256 maxBondAmount;
            (maxBondAmount, success) = YieldSpaceMath
                .calculateMaxBuyBondsOutSafe(
                    HyperdriveMath.calculateEffectiveShareReserves(
                        params.presentValueParams.shareReserves,
                        params.presentValueParams.shareAdjustment
                    ),
                    params.presentValueParams.bondReserves,
                    ONE - params.presentValueParams.timeStretch,
                    params.presentValueParams.vaultSharePrice,
                    params.presentValueParams.initialVaultSharePrice
                );
            assertEq(success, true);
            assertApproxEqAbs(
                maxBondAmount,
                params.presentValueParams.shortsOutstanding,
                params.presentValueParams.shortsOutstanding.mulDown(0.05e18)
            );
        }
    }

    function test__calculateDistributeExcessIdleShareProceeds() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockLPMath lpMath = new MockLPMath();

        uint256 apr = 0.02e18;
        uint256 initialVaultSharePrice = 1e18;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = HyperdriveMath.calculateTimeStretch(
            apr,
            positionDuration
        );

        // The pool is net neutral.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: LPMath.calculatePresentValue(
                        presentValueParams
                    ),
                    activeLpTotalSupply: 1_000_000e18,
                    withdrawalSharesTotalSupply: 1_000e18,
                    idle: 10_000_000e18,
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: shareReserves,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });

            // Calculate the starting LP share price.
            uint256 startingLPSharePrice = LPMath
                .calculatePresentValue(params.presentValueParams)
                .divDown(
                    params.activeLpTotalSupply +
                        params.withdrawalSharesTotalSupply
                );

            // Calculate the original effective share reserves.
            uint256 originalEffectiveShareReserves = HyperdriveMath
                .calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                );

            // Calculate the share proceeds.
            MockLPMath lpMath_ = lpMath; // avoid stack-too-deep
            (uint256 maxShareReservesDelta, bool success) = lpMath_
                .calculateMaxShareReservesDeltaSafe(
                    params,
                    originalEffectiveShareReserves
                );
            assertEq(success, true);
            uint256 shareProceeds = lpMath_
                .calculateDistributeExcessIdleShareProceeds(
                    params,
                    originalEffectiveShareReserves,
                    maxShareReservesDelta
                );

            // Calculate the ending LP share price.
            uint256 endingLPSharePrice;
            {
                (
                    params.presentValueParams.shareReserves,
                    params.presentValueParams.shareAdjustment,
                    params.presentValueParams.bondReserves
                ) = lpMath_.calculateUpdateLiquidity(
                    params.originalShareReserves,
                    params.originalShareAdjustment,
                    params.originalBondReserves,
                    params.presentValueParams.minimumShareReserves,
                    -int256(shareProceeds)
                );
                endingLPSharePrice = LPMath
                    .calculatePresentValue(params.presentValueParams)
                    .divDown(params.activeLpTotalSupply);
            }

            // Ensure that the starting and ending LP share prices are
            // approximately equal.
            assertApproxEqAbs(startingLPSharePrice, endingLPSharePrice, 100);
        }

        // The pool is net long.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 50_000_000e18,
                    longAverageTimeRemaining: 1e18,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: LPMath.calculatePresentValue(
                        presentValueParams
                    ),
                    activeLpTotalSupply: 1_000_000e18,
                    withdrawalSharesTotalSupply: 50_000e18,
                    idle: 10_000_000e18,
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: shareReserves,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });

            // Calculate the starting LP share price.
            uint256 startingLPSharePrice = LPMath
                .calculatePresentValue(params.presentValueParams)
                .divDown(
                    params.activeLpTotalSupply +
                        params.withdrawalSharesTotalSupply
                );

            // Calculate the original effective share reserves.
            uint256 originalEffectiveShareReserves = HyperdriveMath
                .calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                );

            // Calculate the share proceeds.
            MockLPMath lpMath_ = lpMath; // avoid stack-too-deep
            (uint256 maxShareReservesDelta, bool success) = lpMath_
                .calculateMaxShareReservesDeltaSafe(
                    params,
                    originalEffectiveShareReserves
                );
            assertEq(success, true);
            uint256 shareProceeds = lpMath_
                .calculateDistributeExcessIdleShareProceeds(
                    params,
                    originalEffectiveShareReserves,
                    maxShareReservesDelta
                );

            // Calculate the ending LP share price.
            uint256 endingLPSharePrice;
            {
                (
                    params.presentValueParams.shareReserves,
                    params.presentValueParams.shareAdjustment,
                    params.presentValueParams.bondReserves
                ) = lpMath_.calculateUpdateLiquidity(
                    params.originalShareReserves,
                    params.originalShareAdjustment,
                    params.originalBondReserves,
                    params.presentValueParams.minimumShareReserves,
                    -int256(shareProceeds)
                );
                endingLPSharePrice = LPMath
                    .calculatePresentValue(params.presentValueParams)
                    .divDown(params.activeLpTotalSupply);
            }

            // Ensure that the starting and ending LP share prices are
            // approximately equal.
            assertApproxEqAbs(startingLPSharePrice, endingLPSharePrice, 1e9);
        }

        // The pool is net short.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 50_000_000e18,
                    shortAverageTimeRemaining: 1e18
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: LPMath.calculatePresentValue(
                        presentValueParams
                    ),
                    activeLpTotalSupply: 1_000_000e18,
                    withdrawalSharesTotalSupply: 1_000e18,
                    idle: 10_000_000e18,
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: shareReserves,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });

            // Calculate the starting LP share price.
            uint256 startingLPSharePrice = LPMath
                .calculatePresentValue(params.presentValueParams)
                .divDown(
                    params.activeLpTotalSupply +
                        params.withdrawalSharesTotalSupply
                );

            // Calculate the original effective share reserves.
            uint256 originalEffectiveShareReserves = HyperdriveMath
                .calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                );

            // Calculate the share proceeds.
            MockLPMath lpMath_ = lpMath; // avoid stack-too-deep
            (uint256 maxShareReservesDelta, bool success) = lpMath_
                .calculateMaxShareReservesDeltaSafe(
                    params,
                    originalEffectiveShareReserves
                );
            assertEq(success, true);
            uint256 shareProceeds = lpMath_
                .calculateDistributeExcessIdleShareProceeds(
                    params,
                    originalEffectiveShareReserves,
                    maxShareReservesDelta
                );

            // Calculate the ending LP share price.
            uint256 endingLPSharePrice;
            {
                (
                    params.presentValueParams.shareReserves,
                    params.presentValueParams.shareAdjustment,
                    params.presentValueParams.bondReserves
                ) = lpMath_.calculateUpdateLiquidity(
                    params.originalShareReserves,
                    params.originalShareAdjustment,
                    params.originalBondReserves,
                    params.presentValueParams.minimumShareReserves,
                    -int256(shareProceeds)
                );
                endingLPSharePrice = LPMath
                    .calculatePresentValue(params.presentValueParams)
                    .divDown(params.activeLpTotalSupply);
            }

            // Ensure that the starting and ending LP share prices are
            // approximately equal.
            assertApproxEqAbs(startingLPSharePrice, endingLPSharePrice, 1e9);
        }
    }

    function test__calculateDistributeExcessIdleWithdrawalSharesRedeemed()
        external
    {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockLPMath lpMath = new MockLPMath();

        uint256 apr = 0.02e18;
        uint256 initialVaultSharePrice = 1e18;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = HyperdriveMath.calculateTimeStretch(
            apr,
            positionDuration
        );

        // The pool is net neutral.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: LPMath.calculatePresentValue(
                        presentValueParams
                    ),
                    activeLpTotalSupply: 1_000_000e18,
                    withdrawalSharesTotalSupply: 1_000_000e18,
                    idle: 100e18,
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: shareReserves,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });

            // Calculate the starting LP share price.
            uint256 startingLPSharePrice = LPMath
                .calculatePresentValue(params.presentValueParams)
                .divDown(
                    params.activeLpTotalSupply +
                        params.withdrawalSharesTotalSupply
                );

            // Calculate the share proceeds.
            uint256 withdrawalSharesRedeemed = lpMath
                .calculateDistributeExcessIdleWithdrawalSharesRedeemed(
                    params,
                    params.idle
                );

            // Calculate the ending LP share price.
            uint256 endingLPSharePrice;
            {
                (
                    params.presentValueParams.shareReserves,
                    params.presentValueParams.shareAdjustment,
                    params.presentValueParams.bondReserves
                ) = lpMath.calculateUpdateLiquidity(
                    params.originalShareReserves,
                    params.originalShareAdjustment,
                    params.originalBondReserves,
                    params.presentValueParams.minimumShareReserves,
                    -int256(params.idle)
                );
                endingLPSharePrice = LPMath
                    .calculatePresentValue(params.presentValueParams)
                    .divDown(
                        params.activeLpTotalSupply +
                            params.withdrawalSharesTotalSupply -
                            withdrawalSharesRedeemed
                    );
            }

            // Ensure that the starting and ending LP share prices are
            // approximately equal.
            assertApproxEqAbs(startingLPSharePrice, endingLPSharePrice, 100);
        }

        // The pool is net long.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 50_000_000e18,
                    longAverageTimeRemaining: 1e18,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: LPMath.calculatePresentValue(
                        presentValueParams
                    ),
                    activeLpTotalSupply: 1_000_000e18,
                    withdrawalSharesTotalSupply: 1_000_000e18,
                    idle: 100e18,
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: shareReserves,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });

            // Calculate the starting LP share price.
            uint256 startingLPSharePrice = LPMath
                .calculatePresentValue(params.presentValueParams)
                .divDown(
                    params.activeLpTotalSupply +
                        params.withdrawalSharesTotalSupply
                );

            // Calculate the share proceeds.
            uint256 withdrawalSharesRedeemed = lpMath
                .calculateDistributeExcessIdleWithdrawalSharesRedeemed(
                    params,
                    params.idle
                );

            // Calculate the ending LP share price.
            uint256 endingLPSharePrice;
            {
                (
                    params.presentValueParams.shareReserves,
                    params.presentValueParams.shareAdjustment,
                    params.presentValueParams.bondReserves
                ) = lpMath.calculateUpdateLiquidity(
                    params.originalShareReserves,
                    params.originalShareAdjustment,
                    params.originalBondReserves,
                    params.presentValueParams.minimumShareReserves,
                    -int256(params.idle)
                );
                endingLPSharePrice = LPMath
                    .calculatePresentValue(params.presentValueParams)
                    .divDown(
                        params.activeLpTotalSupply +
                            params.withdrawalSharesTotalSupply -
                            withdrawalSharesRedeemed
                    );
            }

            // Ensure that the starting and ending LP share prices are
            // approximately equal.
            assertApproxEqAbs(startingLPSharePrice, endingLPSharePrice, 100);
        }

        // The pool is net short.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 50_000_000e18,
                    shortAverageTimeRemaining: 1e18
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: LPMath.calculatePresentValue(
                        presentValueParams
                    ),
                    activeLpTotalSupply: 1_000_000e18,
                    withdrawalSharesTotalSupply: 1_000_000e18,
                    idle: 100e18,
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: shareReserves,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });

            // Calculate the starting LP share price.
            uint256 startingLPSharePrice = LPMath
                .calculatePresentValue(params.presentValueParams)
                .divDown(
                    params.activeLpTotalSupply +
                        params.withdrawalSharesTotalSupply
                );

            // Calculate the share proceeds.
            uint256 withdrawalSharesRedeemed = lpMath
                .calculateDistributeExcessIdleWithdrawalSharesRedeemed(
                    params,
                    params.idle
                );

            // Calculate the ending LP share price.
            uint256 endingLPSharePrice;
            {
                (
                    params.presentValueParams.shareReserves,
                    params.presentValueParams.shareAdjustment,
                    params.presentValueParams.bondReserves
                ) = lpMath.calculateUpdateLiquidity(
                    params.originalShareReserves,
                    params.originalShareAdjustment,
                    params.originalBondReserves,
                    params.presentValueParams.minimumShareReserves,
                    -int256(params.idle)
                );
                endingLPSharePrice = LPMath
                    .calculatePresentValue(params.presentValueParams)
                    .divDown(
                        params.activeLpTotalSupply +
                            params.withdrawalSharesTotalSupply -
                            withdrawalSharesRedeemed
                    );
            }

            // Ensure that the starting and ending LP share prices are
            // approximately equal.
            assertApproxEqAbs(startingLPSharePrice, endingLPSharePrice, 100);
        }
    }

    function test__calculateDistributeExcessIdleShareProceedsNetLongEdgeCaseSafe()
        external
    {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockLPMath lpMath = new MockLPMath();

        uint256 apr = 0.02e18;
        uint256 initialVaultSharePrice = 1e18;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = HyperdriveMath.calculateTimeStretch(
            apr,
            positionDuration
        );

        // The pool has a shareAdjustment <= 0.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = -1;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: LPMath.calculatePresentValue(
                        presentValueParams
                    ),
                    activeLpTotalSupply: 1_000_000e18,
                    withdrawalSharesTotalSupply: 1_000_000e18,
                    idle: 100e18,
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: shareReserves,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });

            (uint256 shareProceeds, bool success) = lpMath
                .calculateDistributeExcessIdleShareProceedsNetLongEdgeCaseSafe(
                    params
                );
            assertEq(shareProceeds, 0);
            assertEq(success, false);
        }

        // The pool's netFlatTrade >= rhs.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 1;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 1e18,
                    shortAverageTimeRemaining: 0
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: 0,
                    activeLpTotalSupply: 1_000_000e18,
                    withdrawalSharesTotalSupply: 1_000_000e18,
                    idle: 100e18,
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: 0,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });

            (uint256 shareProceeds, bool success) = lpMath
                .calculateDistributeExcessIdleShareProceedsNetLongEdgeCaseSafe(
                    params
                );
            assertEq(shareProceeds, 0);
            assertEq(success, false);
        }

        // The pool's originalShareReserves < rhs.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 1;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialVaultSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    vaultSharePrice: 2e18,
                    initialVaultSharePrice: initialVaultSharePrice,
                    minimumShareReserves: 1e5,
                    minimumTransactionAmount: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 1e18,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            LPMath.DistributeExcessIdleParams memory params = LPMath
                .DistributeExcessIdleParams({
                    presentValueParams: presentValueParams,
                    startingPresentValue: 0,
                    activeLpTotalSupply: 1_000_000e18,
                    withdrawalSharesTotalSupply: 1_000_000e18,
                    idle: 100e18,
                    netCurveTrade: int256(
                        presentValueParams.longsOutstanding.mulDown(
                            presentValueParams.longAverageTimeRemaining
                        )
                    ) -
                        int256(
                            presentValueParams.shortsOutstanding.mulDown(
                                presentValueParams.shortAverageTimeRemaining
                            )
                        ),
                    originalShareReserves: shareReserves,
                    originalShareAdjustment: shareAdjustment,
                    originalBondReserves: bondReserves
                });

            (uint256 shareProceeds, bool success) = lpMath
                .calculateDistributeExcessIdleShareProceedsNetLongEdgeCaseSafe(
                    params
                );
            assertEq(shareProceeds, 0);
            assertEq(success, false);
        }
    }

    function calculateBondReserves(
        uint256 _shareReserves,
        uint256 _initialVaultSharePrice,
        uint256 _apr,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 bondReserves) {
        // Solving for (1 + r * t) ** (1 / tau) here. t is the normalized time
        // remaining which in this case is 1. Because bonds mature after the
        // positionDuration, we need to scale the apr to the proportion of a
        // year of the positionDuration. tau = t / time_stretch, or just
        // 1 / time_stretch in this case.
        uint256 t = _positionDuration.divDown(365 days);
        uint256 tau = ONE.mulDown(_timeStretch);
        uint256 interestFactor = (ONE + _apr.mulDown(t)).pow(ONE.divDown(tau));

        // bondReserves = mu * z * (1 + apr * t) ** (1 / tau)
        bondReserves = _initialVaultSharePrice.mulDown(_shareReserves).mulDown(
            interestFactor
        );
        return bondReserves;
    }
}
