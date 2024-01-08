// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract HyperdriveUtilsTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using Lib for *;

    // This test verifies that the time stretch calculation holds the ratio of
    // reserves constant after different position durations.
    function test_calculateTimeStretch(
        uint256 apr,
        uint256 positionDuration
    ) external {
        // Warp time forward by 50 years to avoid any issues handling long terms.
        vm.warp(50 * 365 days);

        // Normalize the fuzzing parameters to a reasonable range.
        apr = apr.normalizeToRange(0.001e18, 10e18);
        positionDuration = positionDuration.normalizeToRange(
            1 days,
            10 * 365 days
        );

        // Deploy and initialize a pool with the target APR and a position
        // duration of 1 year.
        IHyperdrive.PoolConfig memory config = testConfig(apr, 365 days);
        deploy(alice, config);
        initialize(alice, apr, 100_000_000e18);
        uint256 expectedShareReserves = hyperdrive.getPoolInfo().shareReserves;
        uint256 expectedBondReserves = hyperdrive.getPoolInfo().bondReserves;

        // Deploy and initialize a pool with the target APR and the target
        // position duration.
        config = testConfig(apr, positionDuration);
        config.checkpointDuration = positionDuration;
        deploy(alice, config);
        initialize(alice, apr, 100_000_000e18);

        // Ensure that the ratio of reserves is approximately equal across the
        // two pools.
        assertApproxEqAbs(
            hyperdrive.getPoolInfo().shareReserves.divDown(
                hyperdrive.getPoolInfo().bondReserves
            ),
            expectedShareReserves.divDown(expectedBondReserves),
            1e6
        );
    }
}
