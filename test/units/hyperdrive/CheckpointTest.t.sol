// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Errors } from "contracts/libraries/Errors.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

contract CheckpointTest is HyperdriveTest {
    function test_checkpoint_failure_future_checkpoint() external {
        vm.expectRevert(Errors.InvalidCheckpointTime.selector);
        hyperdrive.checkpoint(block.timestamp + CHECKPOINT_DURATION);
    }

    function test_checkpoint_failure_invalid_checkpoint_time() external {
        vm.expectRevert(Errors.InvalidCheckpointTime.selector);
        hyperdrive.checkpoint(latestCheckpoint() + 1);
    }

    function test_checkpoint_preset_checkpoint() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Open a long and a short.
        (, uint256 longAmount) = openLong(bob, 10_000_000e18);
        uint256 shortAmount = 50_000e18;
        openShort(eve, shortAmount);

        // Update the share price. Since the long and short were opened in this
        // checkpoint, the checkpoint should be of the old checkpoint price.
        uint256 sharePrice = getPoolInfo().sharePrice;
        hyperdrive.setSharePrice(1.5e18);

        // Create a checkpoint.
        uint256 aprBefore = calculateAPRFromReserves(hyperdrive);
        hyperdrive.checkpoint(latestCheckpoint());

        // Ensure that the pool's APR wasn't changed by the checkpoint.
        assertEq(calculateAPRFromReserves(hyperdrive), aprBefore);

        // Ensure that the checkpoint contains the share price prior to the
        // share price update.
        assertEq(hyperdrive.checkpoints(latestCheckpoint()), sharePrice);

        // Ensure that the long and short balance wasn't effected by the
        // checkpoint (the long and short haven't matured yet).
        assertEq(hyperdrive.longsOutstanding(), longAmount);
        assertEq(hyperdrive.shortsOutstanding(), shortAmount);
    }

    function test_checkpoint_latest_checkpoint() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Advance a checkpoint.
        vm.warp(block.timestamp + CHECKPOINT_DURATION);

        // Update the share price. Since the long and short were opened in this
        // checkpoint, the checkpoint should be of the old checkpoint price.
        uint256 sharePrice = 1.5e18;
        hyperdrive.setSharePrice(sharePrice);

        // Create a checkpoint.
        uint256 aprBefore = calculateAPRFromReserves(hyperdrive);
        hyperdrive.checkpoint(latestCheckpoint());

        // Ensure that the pool's APR wasn't changed by the checkpoint.
        assertEq(calculateAPRFromReserves(hyperdrive), aprBefore);

        // Ensure that the checkpoint contains the latest share price.
        assertEq(hyperdrive.checkpoints(latestCheckpoint()), sharePrice);
    }

    function test_checkpoint_redemption() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Open a long and a short.
        openLong(bob, 10_000_000e18);
        uint256 shortAmount = 50_000e18;
        openShort(eve, shortAmount);

        // Advance a term.
        vm.warp(block.timestamp + POSITION_DURATION);

        // Create a checkpoint.
        hyperdrive.checkpoint(latestCheckpoint());

        // TODO: This should be either removed or uncommented when we decide
        // whether or not the flat+curve invariant should have an impact on
        // the market rate.
        //
        // Ensure that the pool's APR wasn't changed by the checkpoint.
        // assertEq(calculateAPRFromReserves(hyperdrive), aprBefore);

        // Ensure that the checkpoint contains the share price prior to the
        // share price update.
        assertEq(
            hyperdrive.checkpoints(latestCheckpoint()),
            getPoolInfo().sharePrice
        );

        // Ensure that the long and short balance has gone to zero (all of the
        // matured positions have been closed).
        assertEq(hyperdrive.longsOutstanding(), 0);
        assertEq(hyperdrive.shortsOutstanding(), 0);
    }

    function test_checkpoint_in_the_past() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Open a long and a short.
        openLong(bob, 10_000_000e18);
        uint256 shortAmount = 50_000e18;
        openShort(eve, shortAmount);

        // Advance a term.
        vm.warp(block.timestamp + POSITION_DURATION);

        // Create a checkpoint.
        hyperdrive.checkpoint(latestCheckpoint());

        uint256 previousCheckpoint = latestCheckpoint() -
            hyperdrive.checkpointDuration();
        hyperdrive.checkpoint(previousCheckpoint);

        // TODO: This should be either removed or uncommented when we decide
        // whether or not the flat+curve invariant should have an impact on
        // the market rate.
        //
        // Ensure that the pool's APR wasn't changed by the checkpoint.
        // assertEq(calculateAPRFromReserves(hyperdrive), aprBefore);

        // Ensure that the checkpoint contains the share price prior to the
        // share price update.
        assertEq(
            hyperdrive.checkpoints(latestCheckpoint()),
            getPoolInfo().sharePrice
        );

        // Ensure that the previous checkpoint contains the closest share price.
        assertEq(
            hyperdrive.checkpoints(previousCheckpoint),
            getPoolInfo().sharePrice
        );

        // Ensure that the long and short balance has gone to zero (all of the
        // matured positions have been closed).
        assertEq(hyperdrive.longsOutstanding(), 0);
        assertEq(hyperdrive.shortsOutstanding(), 0);
    }
}
