// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../utils/HyperdriveTest.sol";

// Validates that HyperdriveTest trade caching is operating correctly
contract TradeDetailsCaching is HyperdriveTest {
    using HyperdriveUtils for IHyperdrive;

    function setUp() public override {
        super.setUp();
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);
    }

    function test_bootstrap_openShortTradeCache_storage() external {
        advanceTime(hyperdrive.maturityTimeFromLatestCheckpoint() - block.timestamp, 0.05e18);

        uint256 t1 = block.timestamp;
        (uint256 m1,) = openShort(alice, 10000e18);
        advanceTime(1 days / 4, 0.05e18);

        uint256 t2 = block.timestamp;
        (uint256 m2,) = openShort(alice, 20000e18);
        advanceTime(1 days / 4, 0.05e18);

        uint256 t3 = block.timestamp;
        (uint256 m3,) = openShort(alice, 20000e18);

        assertEq(m1, m2, "maturities should be the same");
        assertEq(m2, m3, "maturities should be the same");
        assertEq(openShortTradeCache[alice][m1].length, 3, "should have 3 trades cached");
        assertEq(openShortTradeCache[alice][m1][0].timestamp, t1, "timestamp 1 should be cached correctly");
        assertEq(openShortTradeCache[alice][m1][1].timestamp, t2, "timestamp 2 should be cached correctly");
        assertEq(openShortTradeCache[alice][m1][2].timestamp, t3, "timestamp 3 should be cached correctly");
    }
}
