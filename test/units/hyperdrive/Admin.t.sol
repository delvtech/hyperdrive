// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

contract AdminTest is HyperdriveTest {
    function test_update_governance() external {
        // Update the pool's governance address.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        address governance = address(0xdeadbeef);
        factory.updateHyperdriveGovernance(governance);

        // Ensure that governance was updated.
        assertEq(hyperdrive.getPoolConfig().governance, governance);
    }

    function test_update_feeCollector() external {
        // Update the fee collector.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        address feeCollector = address(0xdeadbeef);
        factory.updateFeeCollector(feeCollector);

        // Ensure that the fee collector was updated.
        assertEq(hyperdrive.getPoolConfig().feeCollector, feeCollector);
    }

    function test_update_sweepCollector() external {
        // Update the sweep collector.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        address sweepCollector = address(0xdeadbeef);
        factory.updateSweepCollector(sweepCollector);

        // Ensure that the sweep collector was updated.
        assertEq(hyperdrive.getPoolConfig().sweepCollector, sweepCollector);
    }

    function test_update_checkpointRewarder() external {
        // Update the checkpoint rewarder.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        address checkpointRewarder = address(0xdeadbeef);
        factory.updateCheckpointRewarder(checkpointRewarder);

        // Ensure that the checkpoint rewarder was updated.
        assertEq(
            hyperdrive.getPoolConfig().checkpointRewarder,
            checkpointRewarder
        );
    }

    function test_pause_failure_unauthorized() external {
        // Ensure that an unauthorized user cannot pause the contract.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        hyperdrive.pause(true);
    }

    function test_pause_success() external {
        // Ensure that an authorized pauser can change the pause status.
        vm.stopPrank();
        vm.startPrank(pauser);
        vm.expectEmit(true, true, true, true);
        emit PauseStatusUpdated(true);
        hyperdrive.pause(true);

        // Ensure that the pause status was updated.
        assertTrue(hyperdrive.getMarketState().isPaused);

        // Ensure that governance can change the pause status.
        vm.stopPrank();
        vm.startPrank(hyperdrive.getPoolConfig().governance);
        vm.expectEmit(true, true, true, true);
        emit PauseStatusUpdated(false);
        hyperdrive.pause(false);

        // Ensure that the pause status was updated.
        assertFalse(hyperdrive.getMarketState().isPaused);
    }
}
