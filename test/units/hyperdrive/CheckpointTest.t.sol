// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveTest, HyperdriveUtils, MockHyperdrive, IHyperdrive } from "test/utils/HyperdriveTest.sol";

contract CheckpointTest is HyperdriveTest {
    function test_checkpoint_failure_future_checkpoint() external {
        vm.expectRevert(IHyperdrive.InvalidCheckpointTime.selector);
        hyperdrive.checkpoint(block.timestamp + CHECKPOINT_DURATION);
    }

    function test_checkpoint_failure_invalid_checkpoint_time() external {
        uint256 checkpointTime = HyperdriveUtils.latestCheckpoint(hyperdrive);
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
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        MockHyperdrive(address(hyperdrive)).accrue(CHECKPOINT_DURATION, 0.1e18);

        // Create a checkpoint.
        uint256 aprBefore = HyperdriveUtils.calculateSpotAPR(hyperdrive);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // Ensure that the pool's APR wasn't changed by the checkpoint.
        assertEq(HyperdriveUtils.calculateSpotAPR(hyperdrive), aprBefore);

        // Ensure that the checkpoint contains the share price prior to the
        // share price update.
        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
            HyperdriveUtils.latestCheckpoint(hyperdrive)
        );
        assertEq(checkpoint.vaultSharePrice, vaultSharePrice);

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
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;

        // Create a checkpoint.
        uint256 aprBefore = HyperdriveUtils.calculateSpotAPR(hyperdrive);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // Ensure that the pool's APR wasn't changed by the checkpoint.
        assertEq(HyperdriveUtils.calculateSpotAPR(hyperdrive), aprBefore);

        // Ensure that the checkpoint contains the latest share price.
        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
            HyperdriveUtils.latestCheckpoint(hyperdrive)
        );
        assertEq(checkpoint.vaultSharePrice, vaultSharePrice);
    }

    function test_checkpoint_redemption() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Open a long and a short.
        openLong(bob, 10_000_000e18);
        uint256 shortAmount = 50_000e18;
        openShort(celine, shortAmount);

        // Advance a term.
        vm.warp(block.timestamp + POSITION_DURATION);

        // Create a checkpoint.
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // TODO: This should be either removed or uncommented when we decide
        // whether or not the flat+curve invariant should have an impact on
        // the market rate.
        //
        // Ensure that the pool's APR wasn't changed by the checkpoint.
        // assertEq(calculateSpotAPR(hyperdrive), aprBefore);

        // Ensure that the checkpoint contains the share price prior to the
        // share price update.
        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
            HyperdriveUtils.latestCheckpoint(hyperdrive)
        );
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        assertEq(checkpoint.vaultSharePrice, poolInfo.vaultSharePrice);

        // Ensure that the long and short balance has gone to zero (all of the
        // matured positions have been closed).
        assertEq(poolInfo.longsOutstanding, 0);
        assertEq(poolInfo.shortsOutstanding, 0);
    }

    function test_checkpoint_in_the_past() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Create a checkpoint.
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // Update the share price.
        MockHyperdrive(address(hyperdrive)).accrue(CHECKPOINT_DURATION, .1e18);

        // Create a checkpoint in the past.
        uint256 previousCheckpoint = HyperdriveUtils.latestCheckpoint(
            hyperdrive
        ) - hyperdrive.getPoolConfig().checkpointDuration;
        hyperdrive.checkpoint(previousCheckpoint);

        // Ensure the previous checkpoint contains the share price prior to the
        // update since a more recent checkpoint was already created.
        uint256 latestCheckpointSharePrice = hyperdrive
            .getCheckpoint(HyperdriveUtils.latestCheckpoint(hyperdrive))
            .vaultSharePrice;
        uint256 previousCheckpointSharePrice = hyperdrive
            .getCheckpoint(previousCheckpoint)
            .vaultSharePrice;
        assertEq(latestCheckpointSharePrice, previousCheckpointSharePrice);
    }
}
