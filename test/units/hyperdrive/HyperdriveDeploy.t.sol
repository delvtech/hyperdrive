// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { DsrHyperdriveDeployer } from
    "contracts/src/factory/DsrHyperdriveDeployer.sol";
import { DsrHyperdriveFactory } from
    "contracts/src/factory/DsrHyperdriveFactory.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { DsrManager } from "contracts/test/MockDsrHyperdrive.sol";
import { IHyperdriveDeployer } from
    "contracts/src/interfaces/IHyperdriveDeployer.sol";

contract HyperdriveFactoryTest is HyperdriveTest {
    function test_hyperdrive_factory_admin_functions() external {
        DsrManager manager =
            DsrManager(address(0x373238337Bfe1146fb49989fc222523f83081dDb));

        DsrHyperdriveDeployer simpleDeployer = new DsrHyperdriveDeployer(
            manager
        );

        address[] memory defaults = new address[](1);
        defaults[0] = bob;

        DsrHyperdriveFactory factory = new DsrHyperdriveFactory(
            alice,
            simpleDeployer,
            bob,
            bob,
            IHyperdrive.Fees(0, 0, 0),
            defaults,
            address(manager)
        );
        assertEq(factory.governance(), alice);

        // Bob can't change the implementations
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.Unauthorized.selector);
        factory.updateGovernance(bob);
        vm.expectRevert(Errors.Unauthorized.selector);
        factory.updateImplementation(IHyperdriveDeployer(bob));
        vm.expectRevert(Errors.Unauthorized.selector);
        factory.updateHyperdriveGovernance(bob);
        vm.expectRevert(Errors.Unauthorized.selector);
        factory.updateFeeCollector(bob);
        vm.expectRevert(Errors.Unauthorized.selector);
        factory.updateFees(IHyperdrive.Fees(1, 2, 4));
        vm.expectRevert(Errors.Unauthorized.selector);
        factory.updateDefaultPausers(defaults);
        vm.stopPrank();

        // Alice can change governance and then bob can change implementation
        vm.startPrank(alice);
        factory.updateGovernance(bob);
        assertEq(factory.governance(), bob);
        vm.stopPrank();
        vm.startPrank(bob);
        factory.updateImplementation(IHyperdriveDeployer(bob));
        uint256 counter = factory.versionCounter();
        assertEq(counter, 2);
        assertEq(address(factory.hyperdriveDeployer()), bob);

        // Bob can change the other values as well.
        factory.updateHyperdriveGovernance(alice);
        assertEq(factory.hyperdriveGovernance(), alice);
        factory.updateFees(IHyperdrive.Fees(1, 2, 3));
        (uint256 curve, uint256 flat, uint256 govFee) = factory.fees();
        assertEq(curve, 1);
        assertEq(flat, 2);
        assertEq(govFee, 3);
        defaults[0] = alice;
        factory.updateDefaultPausers(defaults);
        assertEq(factory.defaultPausers(0), alice);
        factory.updateFeeCollector(alice);
        assertEq(factory.feeCollector(), alice);
    }
}
