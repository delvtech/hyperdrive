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
        uint256 lpShares = initialize(alice, 0.02e18, 500_000_000e18);

        // Celine opens  a short
        (uint256 maturityTime0, ) = openShort(celine, 100e18);

        // Most of the term passes.
        advanceTime(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.99e18),
            0
        );

        // Alice removes almost all of her liquidity.
        removeLiquidity(alice, lpShares - 1e5);

        // Bob opens a max short.
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // The remainder of the term elapses and Celine redeems her short.
        advanceTime(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.01e18),
            0
        );
        closeShort(celine, maturityTime0, 100e18);

        console.log(
            "share reserves",
            hyperdrive.getPoolInfo().shareReserves.toString(18)
        );
    }
}
