// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import "test/mocks/MockYieldSpaceMath.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";

contract YieldSpaceMathTest is Test {
    using FixedPointMath for uint256;

    function test__calculateOutGivenIn() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            22.186877016851916266e18
        );
        // test small amount of shares in
        uint256 result1 = yieldSpaceMath.calculateBondsOutGivenSharesIn(
            100000e18, // shareReserves
            100000e18, // bondReserves
            200000e18, // bondReserveAdjustment
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
            100000e18, // bondReserves
            200000e18, // bondReserveAdjustment
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
            100000e18, // bondReserves
            200000e18, // bondReserveAdjustment
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
            100000e18, // bondReserves
            200000e18, // bondReserveAdjustment
            80000e18, // amountIn
            1e18 - FixedPointMath.ONE_18.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult4 = 76850.14470187116e18;
        assertApproxEqAbs(result4, pythonResult4, 1e9);
    }

    // calculateInGivenOut false
    function test__calculateSharesInGivenBondsOut() public {
        MockYieldSpaceMath yieldSpaceMath = new MockYieldSpaceMath();
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            22.186877016851916266e18
        );
        // test small amount of shares in
        uint256 result1 = yieldSpaceMath.calculateBondsInGivenSharesOut(
            100000e18, // shareReserves
            100000e18, // bondReserves
            200000e18, // bondReserveAdjustment
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
            100000e18, // bondReserves
            200000e18, // bondReserveAdjustment
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
            100000e18, // bondReserves
            200000e18, // bondReserveAdjustment
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
            100000e18, // bondReserves
            200000e18, // bondReserveAdjustment
            80000e18, // amountIn
            1e18 - FixedPointMath.ONE_18.divDown(2e18).mulDown(timeStretch), // stretchedTimeElapsed
            1e18, // c
            1e18 // mu
        );
        uint256 pythonResult4 = 78866.87433323538e18;
        assertApproxEqAbs(result4, pythonResult4, 1e9);
    }
}
