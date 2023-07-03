// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { DsrHyperdriveDeployer } from "contracts/src/factory/DsrHyperdriveDeployer.sol";
import { DsrHyperdriveFactory } from "contracts/src/factory/DsrHyperdriveFactory.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { DsrManager } from "contracts/test/MockDsrHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

contract HyperdriveFactoryTest is HyperdriveTest {
    function test_hyperdrive_factory_admin_functions() external {
        // Deploy the DsrHyperdrive factory and deployer.
        DsrManager manager = DsrManager(
            address(0x373238337Bfe1146fb49989fc222523f83081dDb)
        );
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
            address(0),
            bytes32(0),
            address(manager)
        );
        assertEq(factory.governance(), alice);

        // Bob can't change access the admin functions.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateGovernance(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateImplementation(IHyperdriveDeployer(bob));
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateHyperdriveGovernance(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateLinkerFactory(address(uint160(0xdeadbeef)));
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateLinkerCodeHash(bytes32(uint256(0xdeadbeef)));
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateFeeCollector(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateFees(IHyperdrive.Fees(1, 2, 4));
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
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
        factory.updateLinkerFactory(address(uint160(0xdeadbeef)));
        assertEq(factory.linkerFactory(), address(uint160(0xdeadbeef)));
        factory.updateLinkerCodeHash(bytes32(uint256(0xdeadbeef)));
        assertEq(factory.linkerCodeHash(), bytes32(uint256(0xdeadbeef)));
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
