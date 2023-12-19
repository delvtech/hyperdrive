// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { LPMath } from "contracts/src/libraries/LPMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { MockLPMath } from "contracts/test/MockLPMath.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract LPMathTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function test__calculatePresentValue() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockLPMath lpMath = new MockLPMath();

        uint256 apr = 0.02e18;
        uint256 initialSharePrice = 1e18;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = HyperdriveUtils.calculateTimeStretch(apr);

        // no open positions.
        {
            LPMath.PresentValueParams memory params = LPMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    minimumShareReserves: 1e5,
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
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
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
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
                    params.sharePrice,
                    params.initialSharePrice
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
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);
            params.shareReserves -= params.longsOutstanding.divDown(
                params.sharePrice
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
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
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
                    params.sharePrice,
                    params.initialSharePrice
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
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0
                });
            uint256 presentValue = lpMath.calculatePresentValue(params);
            params.shareReserves += params.shortsOutstanding.divDown(
                params.sharePrice
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
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
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
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
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
                    params.sharePrice,
                    params.initialSharePrice
                );
            params.shareReserves -= params.longsOutstanding.divDown(
                params.sharePrice
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
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
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
                    params.sharePrice,
                    params.initialSharePrice
                );
            params.shareReserves += params.shortsOutstanding.divDown(
                params.sharePrice
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
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
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
                    params.sharePrice,
                    params.initialSharePrice
                );
            params.shareReserves +=
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.sharePrice
                ) -
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.sharePrice
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
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
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
                    params.sharePrice,
                    params.initialSharePrice
                );
            params.shareReserves -=
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.sharePrice
                ) -
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.sharePrice
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
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
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
            uint256 maxCurveTrade = YieldSpaceMath.calculateMaxBuyBondsOut(
                uint256(int256(params.shareReserves) - params.shareAdjustment),
                params.bondReserves,
                ONE - params.timeStretch,
                params.sharePrice,
                params.initialSharePrice
            );
            uint256 maxShareProceeds = YieldSpaceMath.calculateMaxBuySharesIn(
                uint256(int256(params.shareReserves) - params.shareAdjustment),
                params.bondReserves,
                ONE - params.timeStretch,
                params.sharePrice,
                params.initialSharePrice
            );
            params.shareReserves += maxShareProceeds;
            params.shareReserves += (netCurveTrade - maxCurveTrade).divDown(
                params.sharePrice
            );

            // Apply the flat part to the reserves.
            params.shareReserves +=
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.sharePrice
                ) -
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.sharePrice
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
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e18,
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
            uint256 maxCurveTrade = YieldSpaceMath.calculateMaxBuyBondsOut(
                uint256(int256(params.shareReserves) - params.shareAdjustment),
                params.bondReserves,
                ONE - params.timeStretch,
                params.sharePrice,
                params.initialSharePrice
            );
            uint256 maxShareProceeds = YieldSpaceMath.calculateMaxBuySharesIn(
                uint256(int256(params.shareReserves) - params.shareAdjustment),
                params.bondReserves,
                ONE - params.timeStretch,
                params.sharePrice,
                params.initialSharePrice
            );
            params.shareReserves += maxShareProceeds;
            params.shareReserves += (netCurveTrade - maxCurveTrade).divDown(
                params.sharePrice
            );

            // Apply the flat part to the reserves.
            params.shareReserves +=
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.sharePrice
                ) -
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.sharePrice
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
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e18,
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
            uint256 maxCurveTrade = YieldSpaceMath.calculateMaxBuyBondsOut(
                uint256(int256(params.shareReserves) - params.shareAdjustment),
                params.bondReserves,
                ONE - params.timeStretch,
                params.sharePrice,
                params.initialSharePrice
            );
            uint256 maxShareProceeds = YieldSpaceMath.calculateMaxBuySharesIn(
                uint256(int256(params.shareReserves) - params.shareAdjustment),
                params.bondReserves,
                ONE - params.timeStretch,
                params.sharePrice,
                params.initialSharePrice
            );
            params.shareReserves += maxShareProceeds;
            params.shareReserves += (netCurveTrade - maxCurveTrade).divDown(
                params.sharePrice
            );

            // Apply the flat part to the reserves.
            params.shareReserves +=
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.sharePrice
                ) -
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.sharePrice
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
        uint256 initialSharePrice = 0.5e18;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = HyperdriveUtils.calculateTimeStretch(apr);

        // The pool is net neutral with no open positions.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    sharePrice: 2e18,
                    initialSharePrice: initialSharePrice,
                    minimumShareReserves: 1e5,
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
            uint256 maxShareReservesDelta = lpMath
                .calculateMaxShareReservesDelta(
                    params,
                    HyperdriveMath.calculateEffectiveShareReserves(
                        shareReserves,
                        shareAdjustment
                    )
                );

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
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    sharePrice: 2e18,
                    initialSharePrice: initialSharePrice,
                    minimumShareReserves: 1e5,
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
            uint256 maxShareReservesDelta = lpMath
                .calculateMaxShareReservesDelta(
                    params,
                    HyperdriveMath.calculateEffectiveShareReserves(
                        shareReserves,
                        shareAdjustment
                    )
                );

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
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    sharePrice: 2e18,
                    initialSharePrice: initialSharePrice,
                    minimumShareReserves: 1e5,
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
            uint256 maxShareReservesDelta = lpMath
                .calculateMaxShareReservesDelta(
                    params,
                    HyperdriveMath.calculateEffectiveShareReserves(
                        shareReserves,
                        shareAdjustment
                    )
                );

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
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    sharePrice: 2e18,
                    initialSharePrice: initialSharePrice,
                    minimumShareReserves: 1e5,
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
            uint256 maxShareReservesDelta = lpMath
                .calculateMaxShareReservesDelta(
                    params,
                    HyperdriveMath.calculateEffectiveShareReserves(
                        shareReserves,
                        shareAdjustment
                    )
                );

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
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    sharePrice: 2e18,
                    initialSharePrice: initialSharePrice,
                    minimumShareReserves: 1e5,
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
            uint256 maxShareReservesDelta = lpMath
                .calculateMaxShareReservesDelta(
                    params,
                    HyperdriveMath.calculateEffectiveShareReserves(
                        shareReserves,
                        shareAdjustment
                    )
                );

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
            uint256 maxBondAmount = YieldSpaceMath.calculateMaxBuyBondsOut(
                HyperdriveMath.calculateEffectiveShareReserves(
                    params.presentValueParams.shareReserves,
                    params.presentValueParams.shareAdjustment
                ),
                params.presentValueParams.bondReserves,
                ONE - params.presentValueParams.timeStretch,
                params.presentValueParams.sharePrice,
                params.presentValueParams.initialSharePrice
            );
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
        uint256 initialSharePrice = 1e18;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = HyperdriveUtils.calculateTimeStretch(apr);

        // The pool is net neutral.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    sharePrice: 2e18,
                    initialSharePrice: initialSharePrice,
                    minimumShareReserves: 1e5,
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

            // Calculate the share proceeds.
            uint256 shareProceeds = lpMath
                .calculateDistributeExcessIdleShareProceeds(
                    params,
                    HyperdriveMath.calculateEffectiveShareReserves(
                        shareReserves,
                        shareAdjustment
                    )
                );

            // Calculate the ending LP share price.
            uint256 endingLPSharePrice;
            {
                (
                    params.presentValueParams.shareReserves,
                    params.presentValueParams.shareAdjustment,
                    params.presentValueParams.bondReserves
                ) = LPMath.calculateUpdateLiquidity(
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
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    sharePrice: 2e18,
                    initialSharePrice: initialSharePrice,
                    minimumShareReserves: 1e5,
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

            // Calculate the share proceeds.
            uint256 shareProceeds = lpMath
                .calculateDistributeExcessIdleShareProceeds(
                    params,
                    HyperdriveMath.calculateEffectiveShareReserves(
                        shareReserves,
                        shareAdjustment
                    )
                );

            // Calculate the ending LP share price.
            uint256 endingLPSharePrice;
            {
                (
                    params.presentValueParams.shareReserves,
                    params.presentValueParams.shareAdjustment,
                    params.presentValueParams.bondReserves
                ) = LPMath.calculateUpdateLiquidity(
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
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    sharePrice: 2e18,
                    initialSharePrice: initialSharePrice,
                    minimumShareReserves: 1e5,
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

            // Calculate the share proceeds.
            uint256 shareProceeds = lpMath
                .calculateDistributeExcessIdleShareProceeds(
                    params,
                    HyperdriveMath.calculateEffectiveShareReserves(
                        shareReserves,
                        shareAdjustment
                    )
                );

            // Calculate the ending LP share price.
            uint256 endingLPSharePrice;
            {
                (
                    params.presentValueParams.shareReserves,
                    params.presentValueParams.shareAdjustment,
                    params.presentValueParams.bondReserves
                ) = LPMath.calculateUpdateLiquidity(
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
        uint256 initialSharePrice = 1e18;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = HyperdriveUtils.calculateTimeStretch(apr);

        // The pool is net neutral.
        {
            uint256 shareReserves = 100_000_000e18;
            int256 shareAdjustment = 0;
            uint256 bondReserves = calculateBondReserves(
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                ),
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    sharePrice: 2e18,
                    initialSharePrice: initialSharePrice,
                    minimumShareReserves: 1e5,
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
                ) = LPMath.calculateUpdateLiquidity(
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
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    sharePrice: 2e18,
                    initialSharePrice: initialSharePrice,
                    minimumShareReserves: 1e5,
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
                ) = LPMath.calculateUpdateLiquidity(
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
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
            LPMath.PresentValueParams memory presentValueParams = LPMath
                .PresentValueParams({
                    shareReserves: shareReserves,
                    shareAdjustment: shareAdjustment,
                    bondReserves: bondReserves,
                    sharePrice: 2e18,
                    initialSharePrice: initialSharePrice,
                    minimumShareReserves: 1e5,
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
                ) = LPMath.calculateUpdateLiquidity(
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

    function calculateBondReserves(
        uint256 _shareReserves,
        uint256 _initialSharePrice,
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
        bondReserves = _initialSharePrice.mulDown(_shareReserves).mulDown(
            interestFactor
        );
        return bondReserves;
    }
}
