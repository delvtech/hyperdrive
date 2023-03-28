// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";

contract ExtremeInputs is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_max_open_long() external {
        // Initialize the pools with a large amount of capital.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Calculate amount of base
        HyperdriveUtils.PoolInfo memory poolInfoBefore = HyperdriveUtils
            .getPoolInfo(hyperdrive);

        // Max base amount
        uint256 baseAmount = HyperdriveUtils.calculateMaxOpenLong(hyperdrive);

        // Open long with max base amount
        (, uint256 bondAmount) = openLong(bob, baseAmount);

        uint256 apr = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);

        HyperdriveUtils.PoolInfo memory poolInfoAfter = HyperdriveUtils
            .getPoolInfo(hyperdrive);

        // FIXME: Can we get a similar check, or is this now
        // fundamentally broken due to the way that the virtual
        // reserves work?
        //
        // assertApproxEqAbs(
        //     poolInfoAfter.bondReserves,
        //     0,
        //     1e15,
        //     "bondReserves should be approximately empty"
        // );

        // Ensure that the ending APR is approximately 0%.
        assertApproxEqAbs(
            apr,
            0,
            0.001e18, // 0% <= APR < 0.001%
            "APR should be approximately 0%"
        );

        // Ensure that the bond reserves were updated to have the correct APR.
        // Due to the way that the flat part of the trade is applied, the bond
        // reserve updates may not exactly correspond to the amount of bonds
        // transferred; however, the pool's APR should be identical to the APR
        // that the bond amount transfer implies.
        assertApproxEqAbs(
            HyperdriveUtils.calculateAPRFromReserves(hyperdrive),
            HyperdriveMath.calculateAPRFromReserves(
                poolInfoAfter.shareReserves,
                poolInfoBefore.bondReserves - bondAmount,
                INITIAL_SHARE_PRICE,
                POSITION_DURATION,
                HyperdriveUtils.getPoolConfig(hyperdrive).timeStretch
            ),
            5
        );
    }
}
