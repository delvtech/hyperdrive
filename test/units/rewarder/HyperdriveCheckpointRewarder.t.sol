// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { VmSafe } from "forge-std/Vm.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdriveCheckpointRewarder } from "../../../contracts/src/interfaces/IHyperdriveCheckpointRewarder.sol";
import { IHyperdriveCheckpointSubrewarder } from "../../../contracts/src/interfaces/IHyperdriveCheckpointSubrewarder.sol";
import { HYPERDRIVE_CHECKPOINT_REWARDER_KIND, VERSION } from "../../../contracts/src/libraries/Constants.sol";
import { HyperdriveCheckpointRewarder } from "../../../contracts/src/rewarder/HyperdriveCheckpointRewarder.sol";
import { HyperdriveCheckpointSubrewarder } from "../../../contracts/src/rewarder/HyperdriveCheckpointSubrewarder.sol";
import { BaseTest } from "../../utils/BaseTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract MockHyperdriveCheckpointSubrewarder {
    IERC20 public rewardToken;
    uint256 public rewardAmount;

    constructor(IERC20 _rewardToken, uint256 _rewardAmount) {
        rewardToken = _rewardToken;
        rewardAmount = _rewardAmount;
    }

    function setRewardToken(IERC20 _rewardToken) external {
        rewardToken = _rewardToken;
    }

    function setRewardAmount(uint256 _rewardAmount) external {
        rewardAmount = _rewardAmount;
    }

    function processReward(
        address,
        address,
        uint256,
        bool
    ) external view returns (IERC20, uint256) {
        return (rewardToken, rewardAmount);
    }
}

contract HyperdriveCheckpointRewarderTest is BaseTest {
    using Lib for *;

    event AdminUpdated(address indexed admin);

    event SubrewarderUpdated(
        IHyperdriveCheckpointSubrewarder indexed subrewarder
    );

    event CheckpointRewardClaimed(
        address indexed instance,
        address indexed claimant,
        bool indexed isTrader,
        uint256 checkpointTime,
        IERC20 rewardToken,
        uint256 rewardAmount
    );

    string internal constant NAME = "HyperdriveCheckpointRewarder";

    MockHyperdriveCheckpointSubrewarder internal subrewarder;
    IHyperdriveCheckpointRewarder internal rewarder;

    function setUp() public override {
        // Run BaseTests's setUp.
        super.setUp();

        // Deploy the hyperdrive checkpoint rewarder.
        vm.stopPrank();
        vm.startPrank(alice);
        subrewarder = new MockHyperdriveCheckpointSubrewarder(
            IERC20(address(0xdeadbeef)),
            1e18
        );
        rewarder = IHyperdriveCheckpointRewarder(
            new HyperdriveCheckpointRewarder(
                NAME,
                IHyperdriveCheckpointSubrewarder(address(subrewarder))
            )
        );

        // Ensure that the admin and name were set correctly.
        assertEq(rewarder.admin(), alice);
        assertEq(rewarder.name(), NAME);
        assertEq(rewarder.kind(), HYPERDRIVE_CHECKPOINT_REWARDER_KIND);
        assertEq(rewarder.version(), VERSION);
    }

    function test_updateAdmin_failure_onlyAdmin() external {
        // Ensure that `updateAdmin` can't be called by an address that isn't
        // the admin.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveCheckpointRewarder.Unauthorized.selector);
        rewarder.updateAdmin(bob);
    }

    function test_updateAdmin_success() external {
        // Ensure that the admin can successfully update the admin address.
        vm.stopPrank();
        vm.startPrank(rewarder.admin());
        vm.expectEmit(true, true, true, true);
        emit AdminUpdated(bob);
        rewarder.updateAdmin(bob);

        // Ensure that the admin was updated successfully.
        assertEq(rewarder.admin(), bob);
    }

    function test_updateSubrewarder_failure_onlyAdmin() external {
        // Ensure that `updateSubrewarder` can't be called by an address that
        // isn't the admin.
        vm.stopPrank();
        vm.startPrank(bob);
        IHyperdriveCheckpointSubrewarder newSubrewarder = IHyperdriveCheckpointSubrewarder(
                address(0xdeadbeef)
            );
        vm.expectRevert(IHyperdriveCheckpointRewarder.Unauthorized.selector);
        rewarder.updateSubrewarder(newSubrewarder);
    }

    function test_updateSubrewarder_success() external {
        // Ensure that the admin can successfully update the subrewarder address.
        vm.stopPrank();
        vm.startPrank(rewarder.admin());
        IHyperdriveCheckpointSubrewarder newSubrewarder = IHyperdriveCheckpointSubrewarder(
                address(0xdeadbeef)
            );
        vm.expectEmit(true, true, true, true);
        emit SubrewarderUpdated(newSubrewarder);
        rewarder.updateSubrewarder(newSubrewarder);

        // Ensure that the subrewarder was updated successfully.
        assertEq(address(rewarder.subrewarder()), address(newSubrewarder));
    }

    function test_claimCheckpointReward_success_zeroAmount() external {
        // Ensure that `claimCheckpointReward` doesn't emit any events when the
        // reward amount is zero.
        subrewarder.setRewardAmount(0);
        vm.recordLogs();
        rewarder.claimCheckpointReward(alice, block.timestamp, true);
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CheckpointRewardClaimed.selector
        );
        assertEq(logs.length, 0);
    }

    function test_claimCheckpointReward_success_nonZeroAmount() external {
        // Ensure that `claimCheckpointReward` emits an event when the reward
        // amount is non-zero.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.recordLogs();
        rewarder.claimCheckpointReward(celine, block.timestamp, true);
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CheckpointRewardClaimed.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(address(uint160(uint256(log.topics[1]))), bob);
        assertEq(address(uint160(uint256(log.topics[2]))), celine);
        assertEq(uint256(log.topics[3]) > 0, true);
        (
            uint256 checkpointTime,
            address rewardToken,
            uint256 rewardAmount
        ) = abi.decode(log.data, (uint256, address, uint256));
        assertEq(checkpointTime, block.timestamp);
        assertEq(rewardToken, address(subrewarder.rewardToken()));
        assertEq(rewardAmount, subrewarder.rewardAmount());
    }
}
