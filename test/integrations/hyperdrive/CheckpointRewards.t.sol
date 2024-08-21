/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { VmSafe } from "forge-std/Vm.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdriveCheckpointRewarder } from "../../../contracts/src/interfaces/IHyperdriveCheckpointRewarder.sol";
import { IHyperdriveCheckpointSubrewarder } from "../../../contracts/src/interfaces/IHyperdriveCheckpointSubrewarder.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveCheckpointRewarder } from "../../../contracts/src/rewarder/HyperdriveCheckpointRewarder.sol";
import { HyperdriveCheckpointSubrewarder } from "../../../contracts/src/rewarder/HyperdriveCheckpointSubrewarder.sol";
import { MockHyperdriveAdminController } from "../../../contracts/test/MockHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract CheckpointRewardsTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using Lib for *;

    event CheckpointRewardClaimed(
        address indexed instance,
        address indexed claimant,
        bool indexed isTrader,
        uint256 checkpointTime,
        IERC20 rewardToken,
        uint256 rewardAmount
    );

    function setUp() public override {
        // Run HyperdriveTests's setUp.
        super.setUp();

        // Instantiate the Hyperdrive checkpoint rewarder, subrewarder, and the
        // wallet that will fund the subrewarder. This subrewarder will pay out
        // its rewards in the base token.
        vm.stopPrank();
        vm.startPrank(alice);
        checkpointRewarder = IHyperdriveCheckpointRewarder(
            new HyperdriveCheckpointRewarder(
                "HyperdriveCheckpointRewarder",
                IHyperdriveCheckpointSubrewarder(address(0))
            )
        );
        IHyperdriveCheckpointSubrewarder checkpointSubrewarder = IHyperdriveCheckpointSubrewarder(
                new HyperdriveCheckpointSubrewarder(
                    "HyperdriveCheckpointSubrewarder",
                    address(checkpointRewarder),
                    rewardSource,
                    registry,
                    IERC20(address(baseToken)),
                    10e18,
                    1e18
                )
            );
        checkpointRewarder.updateSubrewarder(checkpointSubrewarder);
        vm.stopPrank();
        vm.startPrank(rewardSource);
        baseToken.mint(rewardSource, 1_000_000e18);
        baseToken.approve(address(checkpointSubrewarder), 1_000_000e18);

        // Sanity check the checkpoint subrewarder to make sure that the minter
        // and trader amounts are different.
        assertTrue(
            checkpointRewarder.subrewarder().minterRewardAmount() !=
                checkpointRewarder.subrewarder().traderRewardAmount()
        );

        // Deploy and initialize the Hyperdrive instance.
        deploy(alice, testConfig(0.05e18, POSITION_DURATION));
        initialize(alice, 0.05e18, 100_000_000e18);

        // Advance a checkpoint so that we are in a fresh checkpoint.
        advanceTime(hyperdrive.getPoolConfig().checkpointDuration, 0);

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_checkpointReward_success_zeroCheckpointRewarder() external {
        // Set the checkpoint rewarder to the zero address.
        MockHyperdriveAdminController(address(adminController))
            .updateCheckpointRewarder(address(0));

        // Ensure that a checkpoint can be submitted.
        vm.stopPrank();
        vm.startPrank(alice);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

        // Ensure that no `CheckpointRewardClaimed` events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CheckpointRewardClaimed.selector
        );
        assertEq(logs.length, 0);
    }

    function test_checkpointReward_success_eoaCheckpointRewarder() external {
        // Set the checkpoint rewarder to an EOA address.
        MockHyperdriveAdminController(address(adminController))
            .updateCheckpointRewarder(address(0xdeadbeef));

        // Ensure that a checkpoint can be submitted.
        vm.stopPrank();
        vm.startPrank(alice);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

        // Ensure that no `CheckpointRewardClaimed` events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CheckpointRewardClaimed.selector
        );
        assertEq(logs.length, 0);
    }

    function test_checkpointReward_success_zeroRewardAmount() external {
        // Set the minter reward amount to zero..
        vm.stopPrank();
        vm.startPrank(checkpointRewarder.subrewarder().admin());
        checkpointRewarder.subrewarder().updateMinterRewardAmount(0);

        // Ensure that a checkpoint can be submitted.
        vm.stopPrank();
        vm.startPrank(alice);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

        // Ensure that no `CheckpointRewardClaimed` events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CheckpointRewardClaimed.selector
        );
        assertEq(logs.length, 0);
    }

    function test_checkpointReward_success_checkpoint_pastCheckpoint()
        external
    {
        // Advance time by several checkpoint durations.
        advanceTime(hyperdrive.getPoolConfig().checkpointDuration * 3, 0);

        // Submit a checkpoint.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 checkpointTime = hyperdrive.latestCheckpoint() -
            hyperdrive.getPoolConfig().checkpointDuration;
        hyperdrive.checkpoint(checkpointTime, 0);

        // Ensure that no `CheckpointRewardClaimed` events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CheckpointRewardClaimed.selector
        );
        assertEq(logs.length, 0);
    }

    function test_checkpointReward_success_checkpoint() external {
        // Get the token balances before the checkpoint was submitted.
        address source = checkpointRewarder.subrewarder().source();
        uint256 sourceBalanceBefore = baseToken.balanceOf(source);
        uint256 aliceBalanceBefore = baseToken.balanceOf(alice);

        // Submit a checkpoint.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 checkpointTime = hyperdrive.latestCheckpoint();
        hyperdrive.checkpoint(checkpointTime, 0);

        // Ensure that the token balances were updated successfully.
        uint256 rewardAmount = checkpointRewarder
            .subrewarder()
            .minterRewardAmount();
        assertEq(
            baseToken.balanceOf(source),
            sourceBalanceBefore - rewardAmount
        );
        assertEq(baseToken.balanceOf(alice), aliceBalanceBefore + rewardAmount);

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            false
        );
    }

    function test_checkpointReward_success_openLong() external {
        // Get the token balances before the checkpoint was submitted.
        address source = checkpointRewarder.subrewarder().source();
        uint256 sourceBalanceBefore = baseToken.balanceOf(source);
        uint256 aliceBalanceBefore = baseToken.balanceOf(alice);

        // Open a long at the beginning of the checkpoint.
        uint256 checkpointTime = hyperdrive.latestCheckpoint();
        openLong(alice, hyperdrive.calculateMaxLong().mulDown(0.2e18));

        // Ensure that the token balances were updated successfully.
        uint256 rewardAmount = checkpointRewarder
            .subrewarder()
            .traderRewardAmount();
        assertEq(
            baseToken.balanceOf(source),
            sourceBalanceBefore - rewardAmount
        );
        assertEq(baseToken.balanceOf(alice), aliceBalanceBefore + rewardAmount);

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );
    }

    function test_checkpointReward_success_openShort() external {
        // Get the token balances before the checkpoint was submitted.
        address source = checkpointRewarder.subrewarder().source();
        uint256 sourceBalanceBefore = baseToken.balanceOf(source);
        uint256 aliceBalanceBefore = baseToken.balanceOf(alice);

        // Open a short at the beginning of the checkpoint.
        uint256 checkpointTime = hyperdrive.latestCheckpoint();
        openShort(alice, hyperdrive.calculateMaxShort().mulDown(0.2e18));

        // Ensure that the token balances were updated successfully.
        uint256 rewardAmount = checkpointRewarder
            .subrewarder()
            .traderRewardAmount();
        assertEq(
            baseToken.balanceOf(source),
            sourceBalanceBefore - rewardAmount
        );
        assertEq(baseToken.balanceOf(alice), aliceBalanceBefore + rewardAmount);

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );
    }

    function test_checkpointReward_success_closeLong() external {
        // Open a long.
        uint256 checkpointTime = hyperdrive.latestCheckpoint();
        (uint256 maturityTime, uint256 longAmount) = openLong(
            alice,
            hyperdrive.calculateMaxLong().mulDown(0.2e18)
        );

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        uint256 rewardAmount = checkpointRewarder
            .subrewarder()
            .traderRewardAmount();
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );

        // Advance to the next checkpoint.
        advanceTime(hyperdrive.getPoolConfig().checkpointDuration, 0);

        // Get the token balances before the checkpoint was submitted.
        address source = checkpointRewarder.subrewarder().source();
        uint256 sourceBalanceBefore = baseToken.balanceOf(source);
        uint256 aliceBalanceBefore = baseToken.balanceOf(alice);

        // Close the long at the beginning of the next checkpoint.
        checkpointTime = hyperdrive.latestCheckpoint();
        uint256 baseProceeds = closeLong(alice, maturityTime, longAmount);

        // Ensure that the token balances were updated successfully.
        assertEq(
            baseToken.balanceOf(source),
            sourceBalanceBefore - rewardAmount
        );
        assertEq(
            baseToken.balanceOf(alice),
            aliceBalanceBefore + baseProceeds + rewardAmount
        );

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );
    }

    function test_checkpointReward_success_closeLong_pastCheckpoint() external {
        // Open a long.
        uint256 checkpointTime = hyperdrive.latestCheckpoint();
        (uint256 maturityTime, uint256 longAmount) = openLong(
            alice,
            hyperdrive.calculateMaxLong().mulDown(0.2e18)
        );

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        uint256 rewardAmount = checkpointRewarder
            .subrewarder()
            .traderRewardAmount();
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );

        // Advance several checkpoints past the maturity time.
        advanceTime(
            hyperdrive.getPoolConfig().positionDuration +
                hyperdrive.getPoolConfig().checkpointDuration,
            0
        );

        // Close the long. This will mint a checkpoint in the previous
        // checkpoint, but a reward shouldn't be claimed.
        closeLong(alice, maturityTime, longAmount);

        // Ensure that no `CheckpointRewardClaimed` events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CheckpointRewardClaimed.selector
        );
        assertEq(logs.length, 0);
    }

    function test_checkpointReward_success_closeShort() external {
        // Open a short.
        uint256 checkpointTime = hyperdrive.latestCheckpoint();
        uint256 shortAmount = hyperdrive.calculateMaxShort().mulDown(0.2e18);
        (uint256 maturityTime, ) = openShort(alice, shortAmount);

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        uint256 rewardAmount = checkpointRewarder
            .subrewarder()
            .traderRewardAmount();
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );

        // Advance to the next checkpoint.
        advanceTime(hyperdrive.getPoolConfig().checkpointDuration, 0);

        // Get the token balances before the checkpoint was submitted.
        address source = checkpointRewarder.subrewarder().source();
        uint256 sourceBalanceBefore = baseToken.balanceOf(source);
        uint256 aliceBalanceBefore = baseToken.balanceOf(alice);

        // Close the long at the beginning of the next checkpoint.
        checkpointTime = hyperdrive.latestCheckpoint();
        uint256 baseProceeds = closeShort(alice, maturityTime, shortAmount);

        // Ensure that the token balances were updated successfully.
        assertEq(
            baseToken.balanceOf(source),
            sourceBalanceBefore - rewardAmount
        );
        assertEq(
            baseToken.balanceOf(alice),
            aliceBalanceBefore + baseProceeds + rewardAmount
        );

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );
    }

    function test_checkpointReward_success_closeShort_pastCheckpoint()
        external
    {
        // Open a short.
        uint256 checkpointTime = hyperdrive.latestCheckpoint();
        uint256 shortAmount = hyperdrive.calculateMaxShort().mulDown(0.2e18);
        (uint256 maturityTime, ) = openShort(alice, shortAmount);

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        uint256 rewardAmount = checkpointRewarder
            .subrewarder()
            .traderRewardAmount();
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );

        // Advance several checkpoints past the maturity time.
        advanceTime(
            hyperdrive.getPoolConfig().positionDuration +
                hyperdrive.getPoolConfig().checkpointDuration,
            0
        );

        // Close the short. This will mint a checkpoint in the previous
        // checkpoint, but a reward shouldn't be claimed.
        closeShort(alice, maturityTime, shortAmount);

        // Ensure that no `CheckpointRewardClaimed` events were emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CheckpointRewardClaimed.selector
        );
        assertEq(logs.length, 0);
    }

    function test_checkpointReward_success_initializeLiquidity() external {
        // Get the token balances before the checkpoint was submitted.
        address source = checkpointRewarder.subrewarder().source();
        uint256 sourceBalanceBefore = baseToken.balanceOf(source);
        uint256 aliceBalanceBefore = baseToken.balanceOf(alice);

        // Deploy a new Hyperdrive instance.
        deploy(alice, testConfig(0.05e18, POSITION_DURATION));

        // Initialize the Hyperdrive instance.
        uint256 checkpointTime = hyperdrive.latestCheckpoint();
        initialize(alice, 0.05e18, 100_000_000e18);

        // Ensure that the token balances were updated successfully.
        uint256 rewardAmount = checkpointRewarder
            .subrewarder()
            .traderRewardAmount();
        assertEq(
            baseToken.balanceOf(source),
            sourceBalanceBefore - rewardAmount
        );
        assertEq(baseToken.balanceOf(alice), aliceBalanceBefore + rewardAmount);

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );
    }

    function test_checkpointReward_success_addLiquidity() external {
        // Get the token balances before the checkpoint was submitted.
        address source = checkpointRewarder.subrewarder().source();
        uint256 sourceBalanceBefore = baseToken.balanceOf(source);
        uint256 aliceBalanceBefore = baseToken.balanceOf(alice);

        // Add liquidity at the beginning of the checkpoint.
        uint256 checkpointTime = hyperdrive.latestCheckpoint();
        addLiquidity(alice, 100_000_000e18);

        // Ensure that the token balances were updated successfully.
        uint256 rewardAmount = checkpointRewarder
            .subrewarder()
            .traderRewardAmount();
        assertEq(
            baseToken.balanceOf(source),
            sourceBalanceBefore - rewardAmount
        );
        assertEq(baseToken.balanceOf(alice), aliceBalanceBefore + rewardAmount);

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );
    }

    function test_checkpointReward_success_removeLiquidity() external {
        // Add liquidity.
        uint256 checkpointTime = hyperdrive.latestCheckpoint();
        uint256 lpShares = addLiquidity(alice, 100_000_000e18);

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        uint256 rewardAmount = checkpointRewarder
            .subrewarder()
            .traderRewardAmount();
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );

        // Advance to the next checkpoint.
        advanceTime(hyperdrive.getPoolConfig().checkpointDuration, 0);

        // Get the token balances before the checkpoint was submitted.
        address source = checkpointRewarder.subrewarder().source();
        uint256 sourceBalanceBefore = baseToken.balanceOf(source);
        uint256 aliceBalanceBefore = baseToken.balanceOf(alice);

        // Remove liquidity at the beginning of the checkpoint.
        checkpointTime = hyperdrive.latestCheckpoint();
        (uint256 baseProceeds, ) = removeLiquidity(alice, lpShares);

        // Ensure that the token balances were updated successfully.
        assertEq(
            baseToken.balanceOf(source),
            sourceBalanceBefore - rewardAmount
        );
        assertEq(
            baseToken.balanceOf(alice),
            aliceBalanceBefore + baseProceeds + rewardAmount
        );

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );
    }

    function test_checkpointReward_success_redeemWithdrawalShares() external {
        // Alice adds liquidity.
        uint256 checkpointTime = hyperdrive.latestCheckpoint();
        uint256 lpShares = addLiquidity(alice, 100_000_000e18);

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        uint256 rewardAmount = checkpointRewarder
            .subrewarder()
            .traderRewardAmount();
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );

        // Bob opens a large short.
        openShort(bob, hyperdrive.calculateMaxShort());

        // Alice removes her liquidity.
        (, uint256 withdrawalShares) = removeLiquidity(alice, lpShares);
        assertGt(withdrawalShares, 0);

        // Advance to the next checkpoint.
        advanceTime(hyperdrive.getPoolConfig().checkpointDuration, 0);

        // Get the token balances before the checkpoint was submitted.
        address source = checkpointRewarder.subrewarder().source();
        uint256 sourceBalanceBefore = baseToken.balanceOf(source);
        uint256 aliceBalanceBefore = baseToken.balanceOf(alice);

        // Alice redeems withdrawal shares at the beginning of the checkpoint.
        checkpointTime = hyperdrive.latestCheckpoint();
        (uint256 baseProceeds, ) = redeemWithdrawalShares(alice, lpShares);

        // Ensure that the token balances were updated successfully.
        assertEq(
            baseToken.balanceOf(source),
            sourceBalanceBefore - rewardAmount
        );
        assertEq(
            baseToken.balanceOf(alice),
            aliceBalanceBefore + baseProceeds + rewardAmount
        );

        // Ensure that the correct `CheckpointRewardClaimed` events was emitted.
        verifyCheckpointRewardClaimedEvent(
            alice,
            checkpointTime,
            rewardAmount,
            true
        );
    }

    function verifyCheckpointRewardClaimedEvent(
        address _claimant,
        uint256 _checkpointTime,
        uint256 _rewardAmount,
        bool _isTrader
    ) internal {
        // Ensure that there was a `CheckpointRewardClaimed` event emitted.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CheckpointRewardClaimed.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];

        // Ensure that the event topics are correct.
        assertEq(address(uint160(uint256(log.topics[1]))), address(hyperdrive));
        assertEq(address(uint160(uint256(log.topics[2]))), _claimant);
        assertEq(log.topics[3] > 0, _isTrader);

        // Ensure that the event data is correct.
        (
            uint256 checkpointTime,
            address rewardToken,
            uint256 rewardAmount
        ) = abi.decode(log.data, (uint256, address, uint256));
        assertEq(checkpointTime, _checkpointTime);
        assertEq(
            rewardToken,
            address(checkpointRewarder.subrewarder().rewardToken())
        );
        assertEq(rewardAmount, _rewardAmount);
    }
}
