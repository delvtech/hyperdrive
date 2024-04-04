// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils, MockHyperdrive, IHyperdrive } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract CheckpointTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

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

        // Start recording event logs.
        vm.recordLogs();

        // Create a checkpoint.
        uint256 aprBefore = HyperdriveUtils.calculateSpotAPR(hyperdrive);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // Ensure that an event wasn't emitted since this checkpoint was already
        // created.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CreateCheckpoint.selector
        );
        assertEq(logs.length, 0);

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

        // Start recording event logs.
        vm.recordLogs();

        // Create a checkpoint.
        uint256 aprBefore = HyperdriveUtils.calculateSpotAPR(hyperdrive);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // Ensure that the correct event was emitted.
        verifyCheckpointEvent(
            HyperdriveUtils.latestCheckpoint(hyperdrive),
            vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            0,
            0,
            hyperdrive.getPoolInfo().lpSharePrice
        );

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
        (, uint256 longAmount) = openLong(bob, 10_000_000e18);
        uint256 shortAmount = 50_000e18;
        openShort(celine, shortAmount);

        // Advance a term.
        vm.warp(block.timestamp + POSITION_DURATION);

        // Start recording event logs.
        vm.recordLogs();

        // Create a checkpoint.
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // Ensure that the correct event was emitted.
        verifyCheckpointEvent(
            HyperdriveUtils.latestCheckpoint(hyperdrive),
            hyperdrive.getPoolInfo().vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            shortAmount,
            longAmount,
            hyperdrive.getPoolInfo().lpSharePrice
        );

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

        // Bob opens a long.
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            10_000_000e18
        );

        // Celine opens a short.
        uint256 shortAmount = 50_000e18;
        openShort(celine, shortAmount);

        // The term and a checkpoint pass.
        advanceTime(POSITION_DURATION + CHECKPOINT_DURATION, 0.1e18);

        // A checkpoint is created.
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Another term passes.
        advanceTime(POSITION_DURATION, 0.1e18);

        // Start recording event logs.
        vm.recordLogs();

        // The checkpoint that will close Bob and Celine's positions is
        // retroactively minted.
        hyperdrive.checkpoint(maturityTime);

        // Ensure that the correct event was emitted.
        verifyCheckpointEvent(
            maturityTime,
            hyperdrive
                .getCheckpoint(maturityTime + CHECKPOINT_DURATION)
                .vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            shortAmount,
            longAmount,
            hyperdrive.getPoolInfo().lpSharePrice
        );

        // Ensure that the created checkpoint contains the share price of the
        // next checkpoint.
        assertEq(
            hyperdrive.getCheckpoint(maturityTime).vaultSharePrice,
            hyperdrive
                .getCheckpoint(maturityTime + CHECKPOINT_DURATION)
                .vaultSharePrice
        );

        // Ensure that the correct amount of funds were set aside in the zombie
        // share reserves.
        uint256 openVaultSharePrice = hyperdrive
            .getCheckpoint(maturityTime - POSITION_DURATION)
            .vaultSharePrice;
        uint256 closeVaultSharePrice = hyperdrive
            .getCheckpoint(maturityTime)
            .vaultSharePrice;
        assertEq(
            hyperdrive.getPoolInfo().zombieShareReserves,
            longAmount.divDown(hyperdrive.getPoolInfo().vaultSharePrice) +
                shortAmount.mulDivDown(
                    closeVaultSharePrice - openVaultSharePrice,
                    hyperdrive.getPoolInfo().vaultSharePrice
                )
        );
    }

    function test_checkpoint_openLong() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Create a checkpoint.
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Advance to the next checkpoint.
        advanceTime(CHECKPOINT_DURATION, 0.1e18);

        // Start recording event logs.
        vm.recordLogs();

        // Alice opens a long. This should also mint a checkpoint.
        openLong(alice, 10_000_000e18);

        // Ensure that the correct event was emitted.
        verifyCheckpointEvent(
            hyperdrive.latestCheckpoint(),
            hyperdrive.getPoolInfo().vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            0,
            0,
            hyperdrive.getPoolInfo().lpSharePrice
        );

        // Ensure that the checkpoint share price was updated.
        assertEq(
            hyperdrive
                .getCheckpoint(hyperdrive.latestCheckpoint())
                .vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice
        );
    }

    function test_checkpoint_openShort() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Create a checkpoint.
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Advance to the next checkpoint.
        advanceTime(CHECKPOINT_DURATION, 0.1e18);

        // Start recording event logs.
        vm.recordLogs();

        // Alice opens a short. This should also mint a checkpoint.
        openShort(alice, 10_000_000e18);

        // Ensure that the correct event was emitted.
        verifyCheckpointEvent(
            hyperdrive.latestCheckpoint(),
            hyperdrive.getPoolInfo().vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            0,
            0,
            hyperdrive.getPoolInfo().lpSharePrice
        );

        // Ensure that the checkpoint share price was updated.
        assertEq(
            hyperdrive
                .getCheckpoint(hyperdrive.latestCheckpoint())
                .vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice
        );
    }

    function test_checkpoint_addLiquidity() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Create a checkpoint.
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Advance to the next checkpoint.
        advanceTime(CHECKPOINT_DURATION, 0.1e18);

        // Start recording event logs.
        vm.recordLogs();

        // Alice adds liquidity. This should also mint a checkpoint.
        addLiquidity(alice, 10_000_000e18);

        // Ensure that the correct event was emitted.
        verifyCheckpointEvent(
            hyperdrive.latestCheckpoint(),
            hyperdrive.getPoolInfo().vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            0,
            0,
            hyperdrive.getPoolInfo().lpSharePrice
        );

        // Ensure that the checkpoint share price was updated.
        assertEq(
            hyperdrive
                .getCheckpoint(hyperdrive.latestCheckpoint())
                .vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice
        );
    }

    function test_checkpoint_removeLiquidity() external {
        // Initialize the Hyperdrive pool.
        uint256 lpShares = initialize(alice, 0.05e18, 500_000_000e18);

        // Create a checkpoint.
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Advance to the next checkpoint.
        advanceTime(CHECKPOINT_DURATION, 0.1e18);

        // Start recording event logs.
        vm.recordLogs();

        // Alice removes liquidity. This should also mint a checkpoint.
        removeLiquidity(alice, lpShares);

        // Ensure that the correct event was emitted.
        verifyCheckpointEvent(
            hyperdrive.latestCheckpoint(),
            hyperdrive.getPoolInfo().vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            0,
            0,
            hyperdrive.getPoolInfo().lpSharePrice
        );

        // Ensure that the checkpoint share price was updated.
        assertEq(
            hyperdrive
                .getCheckpoint(hyperdrive.latestCheckpoint())
                .vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice
        );
    }

    function test_checkpoint_redeemWithdrawalShares() external {
        // Initialize the Hyperdrive pool.
        uint256 lpShares = initialize(alice, 0.05e18, 500_000_000e18);

        // Bob opens a max short.
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        openShort(bob, shortAmount);

        // Alice removes her liquidity.
        (, uint256 withdrawalShares) = removeLiquidity(alice, lpShares);

        // The term passes.
        advanceTime(POSITION_DURATION, 0.1e18);

        // Start recording event logs.
        vm.recordLogs();

        // Alice redeems her withdrawal shares. This should also mint a checkpoint.
        redeemWithdrawalShares(alice, withdrawalShares);

        // Ensure that the correct event was emitted.
        verifyCheckpointEvent(
            hyperdrive.latestCheckpoint(),
            hyperdrive.getPoolInfo().vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            shortAmount,
            0,
            hyperdrive.getPoolInfo().lpSharePrice
        );

        // Ensure that the checkpoint share price was updated.
        assertApproxEqAbs(
            hyperdrive
                .getCheckpoint(hyperdrive.latestCheckpoint())
                .vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            1
        );
    }

    function test_checkpoint_closeLong_beforeMaturity() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Bob opens a long.
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, 10e18);

        // The checkpoint passes.
        advanceTime(CHECKPOINT_DURATION, 0.1e18);

        // Start recording event logs.
        vm.recordLogs();

        // Bob closes his long. This should also mint a checkpoint.
        closeLong(bob, maturityTime, longAmount);

        // Ensure that the correct event was emitted.
        verifyCheckpointEvent(
            hyperdrive.latestCheckpoint(),
            hyperdrive.getPoolInfo().vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            0,
            0,
            hyperdrive.getPoolInfo().lpSharePrice
        );

        // Ensure that the checkpoint share price was updated.
        assertEq(
            hyperdrive
                .getCheckpoint(hyperdrive.latestCheckpoint())
                .vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice
        );
    }

    function test_checkpoint_closeLong_afterMaturity() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Bob opens a long.
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, 10e18);

        // The term and an additional checkpoint pass.
        advanceTime(POSITION_DURATION + CHECKPOINT_DURATION, 0.1e18);

        // A checkpoint is created.
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Another term passes.
        advanceTime(POSITION_DURATION, 0.1e18);

        // Start recording event logs.
        vm.recordLogs();

        // Bob closes his long. Instead of minting the latest checkpoint, this
        // should mint a past checkpoint. The checkpoint's share price should be
        // the share price of the next checkpoint.
        closeLong(bob, maturityTime, longAmount);

        // Ensure that the correct event was emitted.
        verifyCheckpointEvent(
            maturityTime,
            hyperdrive
                .getCheckpoint(maturityTime + CHECKPOINT_DURATION)
                .vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            0,
            longAmount,
            hyperdrive.getPoolInfo().lpSharePrice
        );

        // Ensure that the checkpoint share price was updated.
        assertEq(
            hyperdrive.getCheckpoint(maturityTime).vaultSharePrice,
            hyperdrive
                .getCheckpoint(maturityTime + CHECKPOINT_DURATION)
                .vaultSharePrice
        );
    }

    function test_checkpoint_closeShort_beforeMaturity() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Bob opens a short.
        uint256 shortAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // The checkpoint passes.
        advanceTime(CHECKPOINT_DURATION, 0.1e18);

        // Start recording event logs.
        vm.recordLogs();

        // Bob closes his short. This should also mint a checkpoint.
        closeShort(bob, maturityTime, shortAmount);

        // Ensure that the correct event was emitted.
        verifyCheckpointEvent(
            hyperdrive.latestCheckpoint(),
            hyperdrive.getPoolInfo().vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            0,
            0,
            hyperdrive.getPoolInfo().lpSharePrice
        );

        // Ensure that the checkpoint share price was updated.
        assertApproxEqAbs(
            hyperdrive
                .getCheckpoint(hyperdrive.latestCheckpoint())
                .vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            1
        );
    }

    function test_checkpoint_closeShort_afterMaturity() external {
        // Initialize the Hyperdrive pool.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Bob opens a short.
        uint256 shortAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // The term and an additional checkpoint pass.
        advanceTime(POSITION_DURATION + CHECKPOINT_DURATION, 0.1e18);

        // A checkpoint is created.
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Another term passes.
        advanceTime(POSITION_DURATION, 0.1e18);

        // Start recording event logs.
        vm.recordLogs();

        // Bob closes his short. Instead of minting the latest checkpoint, this
        // should mint a past checkpoint. The checkpoint's share price should be
        // the share price of the next checkpoint.
        closeShort(bob, maturityTime, shortAmount);

        // Ensure that the correct event was emitted.
        verifyCheckpointEvent(
            maturityTime,
            hyperdrive
                .getCheckpoint(maturityTime + CHECKPOINT_DURATION)
                .vaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice,
            shortAmount,
            0,
            hyperdrive.getPoolInfo().lpSharePrice
        );

        // Ensure that the checkpoint share price was updated.
        assertEq(
            hyperdrive.getCheckpoint(maturityTime).vaultSharePrice,
            hyperdrive
                .getCheckpoint(maturityTime + CHECKPOINT_DURATION)
                .vaultSharePrice
        );
    }

    function verifyCheckpointEvent(
        uint256 checkpointTime,
        uint256 checkpointVaultSharePrice,
        uint256 vaultSharePrice,
        uint256 maturedShorts,
        uint256 maturedLongs,
        uint256 lpSharePrice
    ) internal {
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CreateCheckpoint.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(uint256(log.topics[1]), checkpointTime);
        (
            uint256 eventCheckpointVaultSharePrice,
            uint256 eventVaultSharePrice,
            uint256 eventMaturedShorts,
            uint256 eventMaturedLongs,
            uint256 eventLpSharePrice
        ) = abi.decode(log.data, (uint256, uint256, uint256, uint256, uint256));
        assertApproxEqAbs(
            eventCheckpointVaultSharePrice,
            checkpointVaultSharePrice,
            1
        );
        assertApproxEqAbs(eventVaultSharePrice, vaultSharePrice, 1);
        assertEq(eventMaturedShorts, maturedShorts);
        assertEq(eventMaturedLongs, maturedLongs);
        assertApproxEqAbs(eventLpSharePrice, lpSharePrice, 50);
    }
}
