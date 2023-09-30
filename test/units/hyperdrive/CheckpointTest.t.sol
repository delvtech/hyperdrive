// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { MockHyperdrive } from "test/mocks/MockHyperdrive.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract CheckpointTest is HyperdriveTest {
    using HyperdriveUtils for *;

    function test_checkpoint_failure_future_checkpoint() external {
        vm.expectRevert(IHyperdrive.InvalidCheckpointTime.selector);
        hyperdrive.checkpoint(block.timestamp + CHECKPOINT_DURATION);
    }

    function test_checkpoint_failure_invalid_checkpoint_time() external {
        uint256 checkpointTime = hyperdrive.latestCheckpoint();
        vm.expectRevert(IHyperdrive.InvalidCheckpointTime.selector);
        hyperdrive.checkpoint(checkpointTime + 1);
    }

    function test_checkpoint_preset_checkpoint() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Open a long and a short.
        (, uint256 longAmount) = openLong(bob, 10_000_000e18);
        uint256 shortAmount = 50_000e18;
        openShort(celine, shortAmount);

        // Update the share price. Since the long and short were opened in this
        // checkpoint, the checkpoint should be of the old checkpoint price.
        uint256 sharePrice = hyperdrive.getPoolInfo().sharePrice;
        MockHyperdrive(address(hyperdrive)).accrue(CHECKPOINT_DURATION, 0.1e18);

        // Create a checkpoint.
        uint256 spotRateBefore = hyperdrive.calculateSpotRate();
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Ensure that the pool's spot rate wasn't changed by the checkpoint.
        assertEq(hyperdrive.calculateSpotRate(), spotRateBefore);

        // Ensure that the checkpoint contains the share price prior to the
        // share price update.
        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
            hyperdrive.latestCheckpoint()
        );
        assertEq(checkpoint.sharePrice, sharePrice);

        // Ensure that the long and short balance wasn't effected by the
        // checkpoint (the long and short haven't matured yet).
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();

        assertEq(poolInfo.longsOutstanding, longAmount);
        assertEq(poolInfo.shortsOutstanding, shortAmount);
    }

    function test_checkpoint_latest_checkpoint() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Advance a checkpoint, updating the share price. Since the long and
        // short were opened in this checkpoint, the checkpoint should be of the
        // old checkpoint price.
        advanceTime(CHECKPOINT_DURATION, 0.1e18);
        uint256 sharePrice = hyperdrive.getPoolInfo().sharePrice;

        // Create a checkpoint.
        uint256 spotRateBefore = hyperdrive.calculateSpotRate();
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Ensure that the pool's spot rate wasn't changed by the checkpoint.
        assertEq(hyperdrive.calculateSpotRate(), spotRateBefore);

        // Ensure that the checkpoint contains the latest share price.
        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
            hyperdrive.latestCheckpoint()
        );
        assertEq(checkpoint.sharePrice, sharePrice);
    }

    function test_checkpoint_redemption() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Open a long and a short.
        openLong(bob, 10_000_000e18);
        uint256 shortAmount = 50_000e18;
        openShort(celine, shortAmount);

        // The term passes.
        advanceTime(POSITION_DURATION, 0);

        // Create a checkpoint.
        uint256 spotRateBefore = hyperdrive.calculateSpotRate();
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Ensure that the pool's spot rate wasn't changed by the checkpoint.
        assertEq(hyperdrive.calculateSpotRate(), spotRateBefore);

        // Ensure that the checkpoint contains the share price prior to the
        // share price update.
        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
            hyperdrive.latestCheckpoint()
        );
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        assertEq(checkpoint.sharePrice, poolInfo.sharePrice);

        // Ensure that the long and short balance has gone to zero (all of the
        // matured positions have been closed).
        assertEq(poolInfo.longsOutstanding, 0);
        assertEq(poolInfo.shortsOutstanding, 0);
    }

    function test_checkpoint_in_the_past() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Open a long and a short.
        openLong(bob, 10_000_000e18);
        uint256 shortAmount = 50_000e18;
        openShort(celine, shortAmount);

        // The term passes.
        advanceTime(POSITION_DURATION, 0);

        // Create a checkpoint.
        uint256 spotRateBefore = hyperdrive.calculateSpotRate();
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Create the checkpoint before the latest checkpoint.
        uint256 previousCheckpoint = hyperdrive.latestCheckpoint() -
            hyperdrive.getPoolConfig().checkpointDuration;
        hyperdrive.checkpoint(previousCheckpoint);

        // Ensure that the pool's APR wasn't changed by the checkpoint.
        assertEq(hyperdrive.calculateSpotRate(), spotRateBefore);

        // Ensure that the checkpoint contains the share price prior to the
        // share price update.
        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
            hyperdrive.latestCheckpoint()
        );
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        assertEq(checkpoint.sharePrice, poolInfo.sharePrice);

        // Ensure that the previous checkpoint contains the closest share price.
        checkpoint = hyperdrive.getCheckpoint(previousCheckpoint);
        assertEq(checkpoint.sharePrice, poolInfo.sharePrice);

        // Ensure that the long and short balance has gone to zero (all of the
        // matured positions have been closed).
        assertEq(poolInfo.longsOutstanding, 0);
        assertEq(poolInfo.shortsOutstanding, 0);
    }
}
