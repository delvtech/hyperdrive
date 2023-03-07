// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

contract ExtremeInputs is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_max_open_long() external {
        // Initialize the pools with a large amount of capital.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Calculate amount of base
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Max base amount
        uint256 baseAmount = calculateMaxOpenLong();

        // Open long with max base amount
        (, uint256 bondAmount) = openLong(bob, baseAmount);

        uint256 apr = calculateAPRFromReserves();

        PoolInfo memory poolInfoAfter = getPoolInfo();

        assertApproxEqAbs(
            poolInfoAfter.bondReserves,
            0,
            1e15,
            "bondReserves should be approximately empty"
        );
        assertApproxEqAbs(
            apr,
            0,
            0.001e18, // 0% <= APR < 0.001%
            "APR should be approximately 0%"
        );

        assertEq(
            poolInfoBefore.bondReserves.sub(bondAmount),
            poolInfoAfter.bondReserves,
            "Delta of bondAmount should have occured in bondReserves"
        );
    }
}
