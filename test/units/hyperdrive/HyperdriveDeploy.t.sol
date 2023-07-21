// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626HyperdriveDeployer } from "contracts/src/factory/ERC4626HyperdriveDeployer.sol";
import { ERC4626HyperdriveFactory } from "contracts/src/factory/ERC4626HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { Mock4626, ERC20 } from "../../mocks/Mock4626.sol";
import { MockERC4626Hyperdrive } from "../../mocks/Mock4626Hyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";

contract HyperdriveFactoryTest is HyperdriveTest {
    function test_hyperdrive_factory_admin_functions()
        external
        __mainnet_fork(16_685_972)
    {
        // Deploy the DsrHyperdrive factory and deployer.
        alice = createUser("alice");
        bob = createUser("bob");

        IERC20 dai = IERC20(
            address(0x6B175474E89094C44Da98b954EedeAC495271d0F)
        );

        vm.startPrank(deployer);

        // Deploy the ERC4626Hyperdrive factory and deployer.
        IERC4626 pool = IERC4626(
            address(new Mock4626(ERC20(address(dai)), "yearn dai", "yDai"))
        );

        ERC4626HyperdriveDeployer simpleDeployer = new ERC4626HyperdriveDeployer(
                pool
            );
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ForwarderFactory();
        ERC4626HyperdriveFactory factory = new ERC4626HyperdriveFactory(
            HyperdriveFactory.FactoryConfig(
                alice,
                bob,
                bob,
                IHyperdrive.Fees(0, 0, 0),
                IHyperdrive.Fees(1e18, 1e18, 1e18),
                defaults
            ),
            simpleDeployer,
            address(forwarderFactory),
            forwarderFactory.ERC20LINK_HASH(),
            pool
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
