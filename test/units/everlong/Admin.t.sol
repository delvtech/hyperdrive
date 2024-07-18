// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;
import { IEverlongAdmin } from "contracts/src/interfaces/IEverlongAdmin.sol";
import { EverlongAdmin } from "contracts/src/everlong/EverlongAdmin.sol";
import { EverlongTest } from "test/utils/EverlongTest.sol";

contract EverlongAdminTest is EverlongTest, EverlongAdmin {
    function test_set_admin_failure_unauthorized() external {
        // Ensure that an unauthorized user cannot set the admin address.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IEverlongAdmin.Unauthorized.selector);
        everlong.setAdmin(address(0));
    }

    function test_set_admin_success_deployer() external {
        // Ensure that the deployer can set the admin address.
        vm.expectEmit(true, false, false, true);
        emit AdminUpdated(address(0));
        everlong.setAdmin(address(0));
        assertEq(everlong.admin(), address(0));
    }
}
