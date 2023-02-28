// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";

contract HyperdriveBenchmark is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_benchmark() external {
        // Deploy Hyperdrive.
        deploy(alice, 0.05e18, 0.1e18, 0.1e18);

        // Initialize the market.
        uint256 aliceLpShares = initialize(alice, 0.05e18, 500_000_000e18);

        // Bob opens a long.
        (uint256 longMaturityTime, uint256 longAmount) = openLong(
            bob,
            20_000_000e18
        );

        // Celine opens a short.
        uint256 shortAmount = 20_000_000e18;
        (uint256 shortMaturityTime, ) = openShort(celine, shortAmount);

        // A small amount of time passes.
        vm.warp(block.timestamp + CHECKPOINT_DURATION.mulDown(1.5e18));

        // Bob adds liquidity.
        uint256 bobLpShares = addLiquidity(bob, 500_000_000e18);

        // A small amount of time passes.
        vm.warp(block.timestamp + CHECKPOINT_DURATION.mulDown(0.3e18));

        // Celine closes her short.
        closeShort(celine, shortMaturityTime, shortAmount);

        // Most of the term passes.
        vm.warp(block.timestamp + POSITION_DURATION.mulDown(0.6e18));

        // Alice removes her liquidity.
        removeLiquidity(alice, aliceLpShares);

        // Alice opens a long.
        (uint256 smallLongMaturityTime, uint256 smallLongAmount) = openLong(
            alice,
            3_000e18
        );

        // Most of Alice's new term passes.
        vm.warp(block.timestamp + POSITION_DURATION.mulDown(0.8e18));

        // Celine creates a checkpoint.
        vm.stopPrank();
        vm.startPrank(celine);
        hyperdrive.checkpoint(latestCheckpoint());

        // Bob closes his long.
        closeLong(bob, longMaturityTime, longAmount);

        // Several terms pass.
        vm.warp(block.timestamp + POSITION_DURATION.mulDown(0.8e18));

        // Alice closes her long.
        closeLong(alice, smallLongMaturityTime, smallLongAmount);

        // Bob removes his liquidity.
        removeLiquidity(bob, bobLpShares);
    }
}
