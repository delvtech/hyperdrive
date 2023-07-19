// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../utils/HyperdriveUtils.sol";
import { MockHyperdriveFactory } from "test/mocks/MockHyperdriveFactory.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";

contract MockHyperdriveFactoryTest is HyperdriveTest {
    function test_hyperdrive_factory_fees() external {
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        IHyperdriveDeployer simpleDeployer;
        MockHyperdriveFactory factory = new MockHyperdriveFactory(
            HyperdriveFactory.FactoryConfig(
                alice,
                bob,
                bob,
                IHyperdrive.Fees(0, 0, 0),
                IHyperdrive.Fees(0, 0, 0),
                defaults
            ),
            simpleDeployer,
            address(0),
            bytes32(0)
        );

        assertEq(factory._governance(), alice);
        vm.startPrank(alice);

        // Fees can not exceed maximum fees.
        vm.expectRevert(IHyperdrive.FeeTooHigh.selector);
        factory.updateFees(IHyperdrive.Fees(2e18, 2, 4));
    }

    function test_hyperdrive_factory_max_fees() external {
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        IHyperdriveDeployer simpleDeployer;
        vm.expectRevert(IHyperdrive.MaxFeeTooHigh.selector);
        new MockHyperdriveFactory(
            HyperdriveFactory.FactoryConfig(
                alice,
                bob,
                bob,
                IHyperdrive.Fees(0, 0, 0),
                IHyperdrive.Fees(2e18, 1e18, 1e18),
                defaults
            ),
            simpleDeployer,
            address(0),
            bytes32(0)
        );
    }
}
