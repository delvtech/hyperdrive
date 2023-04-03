// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

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

    function test_bootstrap_openLongTradeCache_storage() external {
        uint256 t1 = block.timestamp;
        (uint256 m1, ) = openLong(alice, 10000e18);
        advanceTime(1 days / 4, 0.05e18);

        uint256 t2 = block.timestamp;
        (uint256 m2, ) = openLong(alice, 20000e18);
        advanceTime(1 days / 4, 0.05e18);

        uint256 t3 = block.timestamp;
        (uint256 m3, ) = openLong(alice, 20000e18);

        assertEq(m1, m2, "maturities should be the same");
        assertEq(m2, m3, "maturities should be the same");
        assertEq(
            openLongTradeCache[alice][m1].length,
            3,
            "should have 3 trades cached"
        );
        assertEq(
            openLongTradeCache[alice][m1][0].timestamp,
            t1,
            "timestamp 1 should be cached correctly"
        );
        assertEq(
            openLongTradeCache[alice][m1][1].timestamp,
            t2,
            "timestamp 2 should be cached correctly"
        );
        assertEq(
            openLongTradeCache[alice][m1][2].timestamp,
            t3,
            "timestamp 3 should be cached correctly"
        );
    }

    function test_bootstrap_closeLongTradeCache_storage() external {
        (uint256 maturityTime, ) = openLong(alice, 100000e18);

        advanceTime(maturityTime - block.timestamp, 0.05e18);

        uint256 t1 = block.timestamp;
        closeLong(alice, maturityTime, 25000e18);
        advanceTime(1 days, 0.05e18);

        uint256 t2 = block.timestamp;
        closeLong(alice, maturityTime, 25000e18);
        advanceTime(POSITION_DURATION, 0.05e18);

        uint256 t3 = block.timestamp;
        closeLong(alice, maturityTime, 50000e18);

        assertEq(
            closeLongTradeCache[alice][maturityTime].length,
            3,
            "should have 3 trades cached"
        );
        assertEq(
            closeLongTradeCache[alice][maturityTime][0].timestamp,
            t1,
            "timestamp 1 should be cached correctly"
        );
        assertEq(
            closeLongTradeCache[alice][maturityTime][1].timestamp,
            t2,
            "timestamp 2 should be cached correctly"
        );
        assertEq(
            closeLongTradeCache[alice][maturityTime][2].timestamp,
            t3,
            "timestamp 3 should be cached correctly"
        );
    }

    function test_bootstrap_openShortTradeCache_storage() external {
        advanceTime(
            hyperdrive.maturityTimeFromLatestCheckpoint() - block.timestamp,
            0.05e18
        );

        uint256 t1 = block.timestamp;
        (uint256 m1, ) = openShort(alice, 10000e18);
        advanceTime(1 days / 4, 0.05e18);

        uint256 t2 = block.timestamp;
        (uint256 m2, ) = openShort(alice, 20000e18);
        advanceTime(1 days / 4, 0.05e18);

        uint256 t3 = block.timestamp;
        (uint256 m3, ) = openShort(alice, 20000e18);

        assertEq(m1, m2, "maturities should be the same");
        assertEq(m2, m3, "maturities should be the same");
        assertEq(
            openShortTradeCache[alice][m1].length,
            3,
            "should have 3 trades cached"
        );
        assertEq(
            openShortTradeCache[alice][m1][0].timestamp,
            t1,
            "timestamp 1 should be cached correctly"
        );
        assertEq(
            openShortTradeCache[alice][m1][1].timestamp,
            t2,
            "timestamp 2 should be cached correctly"
        );
        assertEq(
            openShortTradeCache[alice][m1][2].timestamp,
            t3,
            "timestamp 3 should be cached correctly"
        );
    }

    function test_bootstrap_closeShortTradeCache_storage() external {
        (uint256 maturityTime, ) = openShort(alice, 100000e18);

        advanceTime(maturityTime - block.timestamp, 0.05e18);

        uint256 t1 = block.timestamp;
        closeShort(alice, maturityTime, 25000e18);
        advanceTime(1 days, 0.05e18);

        uint256 t2 = block.timestamp;
        closeShort(alice, maturityTime, 25000e18);
        advanceTime(POSITION_DURATION, 0.05e18);

        uint256 t3 = block.timestamp;
        closeShort(alice, maturityTime, 50000e18);

        assertEq(
            closeShortTradeCache[alice][maturityTime].length,
            3,
            "should have 3 trades cached"
        );
        assertEq(
            closeShortTradeCache[alice][maturityTime][0].timestamp,
            t1,
            "timestamp 1 should be cached correctly"
        );
        assertEq(
            closeShortTradeCache[alice][maturityTime][1].timestamp,
            t2,
            "timestamp 2 should be cached correctly"
        );
        assertEq(
            closeShortTradeCache[alice][maturityTime][2].timestamp,
            t3,
            "timestamp 3 should be cached correctly"
        );
    }
}
