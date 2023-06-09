// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { MockYieldSpaceMath } from "contracts/test/MockYieldSpaceMath.sol";
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

    function test__calculateMaxBuy(
        uint256 z,
        uint256 y,
        uint256 c,
        uint256 mu
    ) external {
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            22.186877016851916266e18
        );
        mu = mu.normalizeToRange(1e18, 3e18); // initial share price
        c = c.normalizeToRange(mu, 3e18); // share price
        uint256 t = 1e18 - timeStretch; // stretchedTimeElapsed

        // Reserves between 1e6 and 100_000_000e6.
        {
            // Simulate a max buy.
            uint256 z_ = z.normalizeToRange(1e6, 100_000_000e6); // share reserves
            uint256 y_ = y.normalizeToRange(
                mu.mulDown(z_).mulDown(1.1e18),
                mu.mulDown(z_).mulDown(10e18)
            ); // bond reserves
            uint256 dz = yieldSpaceMath.calculateMaxBuy(z_, y_, t, c, mu);
            uint256 dy = yieldSpaceMath.calculateBondsOutGivenSharesIn(
                z_,
                y_,
                dz,
                t,
                c,
                mu
            );

            // Ensure that the pool's spot price is very close to 1.
            z_ += dz;
            y_ -= dy;
            assertLe(mu.mulDown(z_), y_);
            assertApproxEqAbs(mu.mulDown(z_), y_, 1e3);
        }

        // Reserves between 1e18 and 100_000_000e18.
        {
            // Simulate a max buy.
            uint256 z_ = z.normalizeToRange(1e18, 100_000_000e18); // share reserves
            uint256 y_ = y.normalizeToRange(
                mu.mulDown(z_).mulDown(1.1e18),
                mu.mulDown(z_).mulDown(10e18)
            ); // bond reserves
            uint256 dz = yieldSpaceMath.calculateMaxBuy(z_, y_, t, c, mu);
            uint256 dy = yieldSpaceMath.calculateBondsOutGivenSharesIn(
                z_,
                y_,
                dz,
                t,
                c,
                mu
            );

            // Ensure that the pool's spot price is very close to 1.
            z_ += dz;
            y_ -= dy;
            assertLe(mu.mulDown(z_), y_);
            assertApproxEqAbs(mu.mulDown(z_), y_, 1e11);
        }
    }

    function test__calculateMaxSell(
        uint256 z,
        uint256 y,
        uint256 c,
        uint256 mu
    ) external {
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            22.186877016851916266e18
        );
        mu = mu.normalizeToRange(1e18, 3e18); // initial share price
        c = c.normalizeToRange(mu, 3e18); // share price
        uint256 t = 1e18 - timeStretch; // stretchedTimeElapsed

        // Reserves between 1e6 and 100_000_000e6.
        {
            // Simulate a max buy.
            uint256 z_ = z.normalizeToRange(1e6, 100_000_000e6); // share reserves
            uint256 y_ = y.normalizeToRange(
                mu.mulDown(z_).mulDown(1.1e18),
                mu.mulDown(z_).mulDown(10e18)
            ); // bond reserves
            uint256 dy = yieldSpaceMath.calculateMaxSell(z_, y_, 0, t, c, mu);
            uint256 dz = yieldSpaceMath.calculateSharesOutGivenBondsIn(
                z_,
                y_,
                dy,
                t,
                c,
                mu
            );

            // Ensure that the pool's share reserves are very close to zero.
            z_ -= dz;
            assertGe(z_, 0);
            assertApproxEqAbs(z_, 0, 1e3);
        }

        // Reserves between 1e18 and 100_000_000e18.
        {
            // Simulate a max buy.
            uint256 z_ = z.normalizeToRange(1e18, 100_000_000e18); // share reserves
            uint256 y_ = y.normalizeToRange(
                mu.mulDown(z_).mulDown(1.1e18),
                mu.mulDown(z_).mulDown(10e18)
            ); // bond reserves
            uint256 dy = yieldSpaceMath.calculateMaxSell(z_, y_, 0, t, c, mu);
            uint256 dz = yieldSpaceMath.calculateSharesOutGivenBondsIn(
                z_,
                y_,
                dy,
                t,
                c,
                mu
            );

            // Ensure that the pool's spot price is very close to 1.
            z_ -= dz;
            assertGe(z_, 0);
            assertApproxEqAbs(z_, 0, 1e11);
        }
    }
}
