// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../../contracts/src/interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveFactory } from "../../../contracts/src/interfaces/IHyperdriveFactory.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

contract AdminTest is HyperdriveTest {
    IHyperdriveFactory internal factory;

    function setUp() public override {
        // Set up the HyperdriveTest tools.
        super.setUp();

        // Redeploy the admin controller using the real Hyperdrive factory.
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        address[] memory pausers = new address[](1);
        pausers[0] = pauser;
        factory = IHyperdriveFactory(
            new HyperdriveFactory(
                HyperdriveFactory.FactoryConfig({
                    governance: config.governance,
                    hyperdriveGovernance: config.governance,
                    deployerCoordinatorManager: alice,
                    defaultPausers: pausers,
                    feeCollector: config.feeCollector,
                    sweepCollector: config.sweepCollector,
                    checkpointRewarder: config.checkpointRewarder,
                    checkpointDurationResolution: 1 hours,
                    minCheckpointDuration: 8 hours,
                    maxCheckpointDuration: 1 days,
                    minPositionDuration: 1 days,
                    maxPositionDuration: 2 * 365 days,
                    minCircuitBreakerDelta: 0.01e18,
                    // NOTE: This is higher than recommended to avoid triggering
                    // this in some tests.
                    maxCircuitBreakerDelta: 2e18,
                    minFixedAPR: 0.01e18,
                    maxFixedAPR: 0.5e18,
                    minTimeStretchAPR: 0.01e18,
                    maxTimeStretchAPR: 0.5e18,
                    minFees: IHyperdrive.Fees({
                        curve: 0.001e18,
                        flat: 0.0001e18,
                        governanceLP: 0.15e18,
                        governanceZombie: 0.03e18
                    }),
                    maxFees: IHyperdrive.Fees({
                        curve: 0.01e18,
                        flat: 0.001e18,
                        governanceLP: 0.15e18,
                        governanceZombie: 0.03e18
                    }),
                    linkerFactory: config.linkerFactory,
                    linkerCodeHash: config.linkerCodeHash
                }),
                "HyperdriveFactory"
            )
        );
        adminController = IHyperdriveAdminController(address(factory));
        deploy(config.governance, config);
    }

    function test_update_governance() external {
        // Update the pool's governance address.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        address governance = address(0xdeadbeef);
        factory.updateHyperdriveGovernance(governance);

        // Ensure that governance was updated.
        assertEq(hyperdrive.getPoolConfig().governance, governance);
    }

    function test_update_feeCollector() external {
        // Update the fee collector.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        address feeCollector = address(0xdeadbeef);
        factory.updateFeeCollector(feeCollector);

        // Ensure that the fee collector was updated.
        assertEq(hyperdrive.getPoolConfig().feeCollector, feeCollector);
    }

    function test_update_sweepCollector() external {
        // Update the sweep collector.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        address sweepCollector = address(0xdeadbeef);
        factory.updateSweepCollector(sweepCollector);

        // Ensure that the sweep collector was updated.
        assertEq(hyperdrive.getPoolConfig().sweepCollector, sweepCollector);
    }

    function test_update_checkpointRewarder() external {
        // Update the checkpoint rewarder.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        address checkpointRewarder = address(0xdeadbeef);
        factory.updateCheckpointRewarder(checkpointRewarder);

        // Ensure that the checkpoint rewarder was updated.
        assertEq(
            hyperdrive.getPoolConfig().checkpointRewarder,
            checkpointRewarder
        );
    }

    function test_update_default_pausers() external {
        // Update the default pausers.
        vm.stopPrank();
        vm.startPrank(factory.governance());
        address[] memory pausers = new address[](4);
        pausers[0] = address(0x1);
        pausers[1] = address(0x2);
        pausers[2] = address(0x3);
        pausers[3] = address(0x4);
        factory.updateDefaultPausers(pausers);

        // Ensure that the new addresses are pausers and that the old pauser is
        // no longer a pauser.
        assertEq(hyperdrive.isPauser(pauser), false);
        for (uint256 i = 0; i < pausers.length; i++) {
            assertEq(hyperdrive.isPauser(pausers[i]), true);
        }
    }

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
