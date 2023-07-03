// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

// FIXME
import "forge-std/console.sol";

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract ExampleTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    function test_example() external {
        // Alice initializes the pool.
        initialize(alice, 0.02e18, 500_000_000e6);

        // Celine opens  a short
        uint256 shortAmount0 = 100e6;
        (uint256 maturityTime0, ) = openShort(celine, shortAmount0);

        // Most of the term passes.
        advanceTime(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.99e18),
            0
        );

        // Bob opens a max short.
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        openShort(bob, shortAmount);

        // The remainder of the term elapses and Celine redeems her short.
        advanceTime(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.01e18),
            0
        );
        closeShort(celine, maturityTime0, shortAmount0);

        // Ensure that the share reserves are equal to zero. This illustrates
        // that the LPs will lose all of the money that should have been
        // returned to the pool.
        assertEq(hyperdrive.getPoolInfo().shareReserves, 0);
    }
}
