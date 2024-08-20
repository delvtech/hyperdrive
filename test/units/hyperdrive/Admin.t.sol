// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

contract AdminTest is HyperdriveTest {
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
