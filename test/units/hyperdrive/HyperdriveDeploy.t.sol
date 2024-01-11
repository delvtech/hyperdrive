// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";

contract HyperdriveFactoryTest is HyperdriveTest {
    function test_hyperdrive_factory_admin_functions()
        external
        __mainnet_fork(16_685_972)
    {
        // Deploy the DsrHyperdrive factory and deployer.
        alice = createUser("alice");
        bob = createUser("bob");

        vm.startPrank(deployer);

        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ForwarderFactory();
        HyperdriveFactory factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                defaultPausers: defaults,
                feeCollector: bob,
                fees: IHyperdrive.Fees(0, 0, 0, 0),
                maxFees: IHyperdrive.Fees(1e18, 1e18, 1e18, 1e18),
                linkerFactory: address(forwarderFactory),
                linkerCodeHash: forwarderFactory.ERC20LINK_HASH()
            })
        );

        address hyperdriveDeployer = makeAddr("hyperdriveDeployer");

        assertEq(factory.governance(), alice);

        // Bob can't access the admin functions.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateGovernance(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateHyperdriveGovernance(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateLinkerFactory(address(uint160(0xdeadbeef)));
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateLinkerCodeHash(bytes32(uint256(0xdeadbeef)));
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateFeeCollector(bob);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateFees(IHyperdrive.Fees(1, 2, 4, 5));
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.updateDefaultPausers(defaults);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.addHyperdriveDeployer(hyperdriveDeployer);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        factory.removeHyperdriveDeployer(hyperdriveDeployer, 0);
        vm.stopPrank();

        // Alice can change governance.
        vm.startPrank(alice);
        factory.updateGovernance(bob);
        assertEq(factory.governance(), bob);
        vm.stopPrank();

        // Bob can change the other values.
        vm.startPrank(bob);
        factory.updateHyperdriveGovernance(alice);
        assertEq(factory.hyperdriveGovernance(), alice);
        factory.updateLinkerFactory(address(uint160(0xdeadbeef)));
        assertEq(factory.linkerFactory(), address(uint160(0xdeadbeef)));
        factory.updateLinkerCodeHash(bytes32(uint256(0xdeadbeef)));
        assertEq(factory.linkerCodeHash(), bytes32(uint256(0xdeadbeef)));
        factory.updateFees(IHyperdrive.Fees(1, 2, 3, 4));
        (
            uint256 curve,
            uint256 flat,
            uint256 govLPFee,
            uint256 govZombieFee
        ) = factory.fees();
        assertEq(curve, 1);
        assertEq(flat, 2);
        assertEq(govLPFee, 3);
        assertEq(govZombieFee, 4);
        defaults[0] = alice;
        factory.updateDefaultPausers(defaults);
        address[] memory updateDefaultPausers = factory.getDefaultPausers();
        assertEq(updateDefaultPausers.length, 1);
        assertEq(updateDefaultPausers[0], alice);
        factory.updateFeeCollector(alice);
        assertEq(factory.feeCollector(), alice);
        factory.addHyperdriveDeployer(hyperdriveDeployer);
        assertEq(factory.isHyperdriveDeployer(hyperdriveDeployer), true);
        factory.removeHyperdriveDeployer(hyperdriveDeployer, 0);
        assertEq(factory.isHyperdriveDeployer(hyperdriveDeployer), false);
    }
}
