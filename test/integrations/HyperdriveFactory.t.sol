// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { MockHyperdriveDeployer, MockHyperdriveTargetDeployer } from "contracts/test/MockHyperdriveDeployer.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract HyperdriveFactoryTest is HyperdriveTest {
    function test_hyperdrive_factory_fees() external {
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        HyperdriveFactory factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                fees: IHyperdrive.Fees(0, 0, 0),
                maxFees: IHyperdrive.Fees(0, 0, 0),
                hyperdriveDeployer: new MockHyperdriveDeployer(),
                target0Deployer: new MockHyperdriveTargetDeployer(),
                target1Deployer: new MockHyperdriveTargetDeployer(),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            })
        );

        assertEq(factory.governance(), alice);
        vm.startPrank(alice);

        // Curve fee can not exceed maximum curve fee.
        vm.expectRevert(IHyperdrive.FeeTooHigh.selector);
        factory.updateFees(IHyperdrive.Fees(2e18, 0, 0));

        // Flat fee can not exceed maximum flat fee.
        vm.expectRevert(IHyperdrive.FeeTooHigh.selector);
        factory.updateFees(IHyperdrive.Fees(0, 2e18, 0));

        // Governance fee can not exceed maximum governance fee.
        vm.expectRevert(IHyperdrive.FeeTooHigh.selector);
        factory.updateFees(IHyperdrive.Fees(0, 0, 2e18));
    }

    // Ensure that the maximum curve fee can not exceed 100%.
    function test_hyperdrive_factory_max_fees() external {
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        HyperdriveFactory.FactoryConfig memory config = HyperdriveFactory
            .FactoryConfig({
                governance: alice,
                hyperdriveGovernance: bob,
                feeCollector: bob,
                defaultPausers: defaults,
                fees: IHyperdrive.Fees(0, 0, 0),
                maxFees: IHyperdrive.Fees(0, 0, 0),
                hyperdriveDeployer: new MockHyperdriveDeployer(),
                target0Deployer: new MockHyperdriveTargetDeployer(),
                target1Deployer: new MockHyperdriveTargetDeployer(),
                linkerFactory: address(0),
                linkerCodeHash: bytes32(0)
            });

        // Ensure that the maximum curve fee can not exceed 100%.
        vm.expectRevert(IHyperdrive.MaxFeeTooHigh.selector);
        config.maxFees.curve = 2e18;
        new HyperdriveFactory(config);
        config.maxFees.curve = 0;

        // Ensure that the maximum flat fee can not exceed 100%.
        vm.expectRevert(IHyperdrive.MaxFeeTooHigh.selector);
        config.maxFees.flat = 2e18;
        new HyperdriveFactory(config);
        config.maxFees.flat = 0;

        // Ensure that the maximum governance fee can not exceed 100%.
        vm.expectRevert(IHyperdrive.MaxFeeTooHigh.selector);
        config.maxFees.governance = 2e18;
        new HyperdriveFactory(config);
        config.maxFees.governance = 0;
    }
}
