// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";

contract AdminTest is HyperdriveTest {
    function test_pause_failure_unauthorized() external {
        // Ensure that an unauthorized user cannot pause the contract.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        hyperdrive.pause(true);
    }

    function test_pause_success() external {
        // Ensure that an authorized pauser can pause the contract.
        vm.stopPrank();
        vm.startPrank(pauser);
        vm.expectEmit(true, true, true, true);
        emit PauseStatusUpdated(true);
        hyperdrive.pause(true);

        // Ensure that the pause status was updated.
        assert(hyperdrive.getMarketState().isPaused);
    }

    function test_setFeeCollector_failure_unauthorized() external {
        // Ensure that an unauthorized user cannot set the fee collector
        // address.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        hyperdrive.setFeeCollector(alice);
    }

    function test_setFeeCollector_success() external {
        address newFeeCollector = alice;

        // Ensure that governance can set the fee collector address.
        vm.stopPrank();
        vm.startPrank(hyperdrive.getPoolConfig().governance);
        vm.expectEmit(true, true, true, true);
        emit FeeCollectorUpdated(newFeeCollector);
        hyperdrive.setFeeCollector(newFeeCollector);

        // Ensure that the fee collector address was updated.
        assertEq(hyperdrive.getPoolConfig().feeCollector, newFeeCollector);
    }

    function test_setSweepCollector_failure_unauthorized() external {
        // Ensure that an unauthorized user cannot set the sweep collector
        // address.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        hyperdrive.setSweepCollector(alice);
    }

    function test_setSweepCollector_success() external {
        address newSweepCollector = alice;

        // Ensure that governance can set the sweep collector address.
        vm.stopPrank();
        vm.startPrank(hyperdrive.getPoolConfig().governance);
        vm.expectEmit(true, true, true, true);
        emit SweepCollectorUpdated(newSweepCollector);
        hyperdrive.setSweepCollector(newSweepCollector);

        // Ensure that the governance address was updated.
        assertEq(hyperdrive.getPoolConfig().sweepCollector, newSweepCollector);
    }

    function test_setGovernance_failure_unauthorized() external {
        // Ensure that an unauthorized user cannot set the governance address.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        hyperdrive.setGovernance(alice);
    }

    function test_setGovernance_success() external {
        address newGovernance = alice;

        // Ensure that governance can set the governance address.
        vm.stopPrank();
        vm.startPrank(hyperdrive.getPoolConfig().governance);
        vm.expectEmit(true, true, true, true);
        emit GovernanceUpdated(newGovernance);
        hyperdrive.setGovernance(newGovernance);

        // Ensure that the governance address was updated.
        assertEq(hyperdrive.getPoolConfig().governance, newGovernance);
    }

    function test_setPauser_failure_unauthorized() external {
        // Ensure that an unauthorized user cannot set a pauser address.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        hyperdrive.setPauser(alice, true);
    }

    function test_setPauser_success() external {
        address newPauser = alice;

        // Ensure that governance can set the governance address.
        vm.stopPrank();
        vm.startPrank(hyperdrive.getPoolConfig().governance);
        vm.expectEmit(true, true, true, true);
        emit PauserUpdated(newPauser, true);
        hyperdrive.setPauser(newPauser, true);

        // Ensure that the pauser address was updated.
        assert(hyperdrive.isPauser(newPauser));
    }
}
