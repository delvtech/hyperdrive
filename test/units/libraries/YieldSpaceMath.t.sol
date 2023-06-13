// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { MockYieldSpaceMath } from "contracts/test/MockYieldSpaceMath.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract YieldSpaceMathTest is Test {
    using FixedPointMath for uint256;
    using Lib for *;

    function test__calculateOutGivenIn() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            22.186877016851916266e18
        );
        // test small amount of shares in
        uint256 result1 = yieldSpaceMath.calculateBondsOutGivenSharesIn(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            100e18, // amountIn
            1e18 - FixedPointMath.ONE_18.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult1 = 102.50516899477225e18;
        assertApproxEqAbs(result1, pythonResult1, 1e9);

        // test large amount shares in
        uint256 result2 = yieldSpaceMath.calculateBondsOutGivenSharesIn(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            80000e18, // amountIn
            1e18 - FixedPointMath.ONE_18.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult2 = 81138.27602200207e18;
        assertApproxEqAbs(result2, pythonResult2, 1e9);

        // test small amount bond in
        uint256 result3 = yieldSpaceMath.calculateSharesOutGivenBondsIn(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            100e18, // amountIn
            1e18 - FixedPointMath.ONE_18.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult3 = 97.55314236719278e18;
        assertApproxEqAbs(result3, pythonResult3, 1e9);

        // test large amount bond in
        uint256 result4 = yieldSpaceMath.calculateSharesOutGivenBondsIn(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            80000e18, // amountIn
            1e18 - FixedPointMath.ONE_18.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult4 = 76850.14470187116e18;
        assertApproxEqAbs(result4, pythonResult4, 1e9);
    }

    // calculateInGivenOut false
    function test__calculateSharesInGivenBondsOut() external {
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            22.186877016851916266e18
        );
        // test small amount of shares in
        uint256 result1 = yieldSpaceMath.calculateBondsInGivenSharesOut(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            100e18, // amountIn
            1e18 - FixedPointMath.ONE_18.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult1 = 102.50826839753427e18;
        assertApproxEqAbs(result1, pythonResult1, 1e9);

        // test large amount shares in
        uint256 result2 = yieldSpaceMath.calculateBondsInGivenSharesOut(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            80000e18, // amountIn
            1e18 - FixedPointMath.ONE_18.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult2 = 83360.61360923108e18;
        assertApproxEqAbs(result2, pythonResult2, 1e9);

        // test small amount bond in
        uint256 result3 = yieldSpaceMath.calculateSharesInGivenBondsOut(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            100e18, // amountIn
            1e18 - FixedPointMath.ONE_18.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult3 = 97.55601990513969e18;
        assertApproxEqAbs(result3, pythonResult3, 1e9);

        // test large amount bond in
        uint256 result4 = yieldSpaceMath.calculateSharesInGivenBondsOut(
            100000e18, // shareReserves
            100000e18 + 200000e18, // bondReserves + s
            80000e18, // amountIn
            1e18 - FixedPointMath.ONE_18.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult4 = 78866.87433323538e18;
        assertApproxEqAbs(result4, pythonResult4, 1e9);
    }

    // This test verifies that sane values won't result in the YieldSpace math
    // functions returning zero.
    function test__calculateSharesInGivenBondsOut__extremeValues(
        uint256 fixedRate,
        uint256 shareReserves,
        uint256 sharePrice,
        uint256 initialSharePrice,
        uint256 tradeSize
    ) external {
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();

        fixedRate = fixedRate.normalizeToRange(0.01e18, 1e18);
        initialSharePrice = initialSharePrice.normalizeToRange(0.8e18, 5e18);
        sharePrice = sharePrice.normalizeToRange(initialSharePrice, 5e18);

        // Test a large span of orders of magnitudes of both the reserves and
        // the size of the reserves. This test demonstrates that for the
        // expected range of reserves reserves, the YieldSpaceMath will only
        // return zero for tiny amounts of tokens.
        for (uint256 i = 6; i <= 18; i += 1) {
            shareReserves = shareReserves.normalizeToRange(
                10 ** (i + 1),
                10 ** (i + 9)
            );
            for (uint256 j = i - (i / 2 + 1); j < i; j++) {
                // Calculate the bond reserves that give the pool the expected spot rate.
                uint256 timeStretch = HyperdriveUtils.calculateTimeStretch(
                    fixedRate
                );
                uint256 bondReserves = HyperdriveMath
                    .calculateInitialBondReserves(
                        shareReserves,
                        initialSharePrice,
                        fixedRate,
                        365 days,
                        timeStretch
                    );
                tradeSize = tradeSize.normalizeToRange(
                    10 ** j,
                    HyperdriveMath
                        .calculateMaxLong(
                            shareReserves,
                            bondReserves,
                            0,
                            timeStretch,
                            sharePrice,
                            initialSharePrice,
                            15
                        )
                        .baseAmount
                );
                uint256 result = yieldSpaceMath.calculateSharesInGivenBondsOut(
                    shareReserves,
                    bondReserves,
                    tradeSize,
                    1e18 - FixedPointMath.ONE_18.mulDown(timeStretch),
                    sharePrice,
                    initialSharePrice
                );
                assertGt(result, 0);
            }
        }
    }

    function test__calculateMaxBuy(
        uint256 fixedRate,
        uint256 shareReserves,
        uint256 sharePrice,
        uint256 initialSharePrice
    ) external {
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();

        fixedRate = fixedRate.normalizeToRange(0.01e18, 1e18);
        shareReserves = shareReserves.normalizeToRange(
            0.0001e18,
            500_000_000e18
        );
        initialSharePrice = initialSharePrice.normalizeToRange(0.8e18, 5e18);
        sharePrice = sharePrice.normalizeToRange(initialSharePrice, 5e18);

        // Calculate the bond reserves that give the pool the expected spot rate.
        uint256 timeStretch = HyperdriveUtils.calculateTimeStretch(fixedRate);
        uint256 bondReserves = HyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            initialSharePrice,
            fixedRate,
            365 days,
            timeStretch
        );

        // Calculate the difference in share and bond reserves caused by the max
        // purchase.
        (uint256 maxDz, uint256 maxDy) = yieldSpaceMath.calculateMaxBuy(
            shareReserves,
            bondReserves,
            1e18 - FixedPointMath.ONE_18.mulDown(timeStretch),
            sharePrice,
            initialSharePrice
        );

        // Ensure that the maximum buy is a valid trade on this invariant and
        // that the ending spot price is close to 1.
        assertApproxEqAbs(
            yieldSpaceMath.modifiedYieldSpaceConstant(
                sharePrice.divDown(initialSharePrice),
                initialSharePrice,
                shareReserves,
                FixedPointMath.ONE_18 - timeStretch,
                bondReserves
            ),
            yieldSpaceMath.modifiedYieldSpaceConstant(
                sharePrice.divDown(initialSharePrice),
                initialSharePrice,
                shareReserves + maxDz,
                FixedPointMath.ONE_18 - timeStretch,
                bondReserves - maxDy
            ),
            1e12 // TODO: Investigate this bound.
        );
        assertApproxEqAbs(
            HyperdriveMath.calculateSpotPrice(
                shareReserves + maxDz,
                bondReserves - maxDy,
                initialSharePrice,
                FixedPointMath.ONE_18,
                timeStretch
            ),
            1e18,
            1e7
        );
    }
}
