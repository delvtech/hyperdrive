// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { MakerDsrHyperdriveDeployer } from "contracts/src/factory/MakerDsrHyperdriveDeployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { DsrManager } from "contracts/test/MockMakerDsrHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";

contract HyperdriveFactoryTest is HyperdriveTest {
    function test_hyperdrive_factory_admin_functions() external {
        DsrManager manager = DsrManager(
            address(0x373238337Bfe1146fb49989fc222523f83081dDb)
        );

        MakerDsrHyperdriveDeployer simpleDeployer = new MakerDsrHyperdriveDeployer(
                manager
            );

        HyperdriveFactory factory = new HyperdriveFactory(
            alice,
            simpleDeployer,
            bob
        );
        assertEq(factory.governance(), alice);

        // Bob can't change the implementations
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.Unauthorized.selector);
        factory.updateGovernance(bob);
        vm.expectRevert(Errors.Unauthorized.selector);
        factory.updateImplementation(IHyperdriveDeployer(bob));
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
    }
}
