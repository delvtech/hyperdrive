// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC4626HyperdriveCoreDeployer } from "../../../contracts/src/deployers/erc4626/ERC4626HyperdriveCoreDeployer.sol";
import { ERC4626HyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/erc4626/ERC4626HyperdriveDeployerCoordinator.sol";
import { ERC4626Target0Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target0Deployer.sol";
import { ERC4626Target1Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target1Deployer.sol";
import { ERC4626Target2Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target2Deployer.sol";
import { ERC4626Target3Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target3Deployer.sol";
import { ERC4626Target4Deployer } from "../../../contracts/src/deployers/erc4626/ERC4626Target4Deployer.sol";
import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../../contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "../../../contracts/src/interfaces/IHyperdriveDeployerCoordinator.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { ERC20ForwarderFactory } from "../../../contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "../../../contracts/test/MockERC4626.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";
import { ERC4626ValidationTest } from "./ERC4626Validation.t.sol";

contract UsdcERC4626 is ERC4626ValidationTest {
    using FixedPointMath for *;
    using Lib for *;

    function setUp() public override {
        super.setUp();
        vm.startPrank(deployer);
        decimals = 6;
        underlyingToken = IERC20(
            address(
                new ERC20Mintable(
                    "usdc",
                    "USDC",
                    6,
                    address(this),
                    false,
                    type(uint256).max
                )
            )
        );
        token = IERC4626(
            address(
                new MockERC4626(
                    ERC20Mintable(address(underlyingToken)),
                    "yearn usdc",
                    "yUSDC",
                    0,
                    address(0),
                    false,
                    type(uint256).max
                )
            )
        );
        uint256 monies = 1_000_000_000e6;
        ERC20Mintable(address(underlyingToken)).mint(deployer, monies);
        ERC20Mintable(address(underlyingToken)).mint(alice, monies);
        ERC20Mintable(address(underlyingToken)).mint(bob, monies);

        // Deploy the Hyperdrive factory and deployer coordinator.
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ERC20ForwarderFactory("ForwarderFactory");
        factory = new HyperdriveFactory(
            HyperdriveFactory.FactoryConfig({
                governance: alice,
                deployerCoordinatorManager: celine,
                hyperdriveGovernance: bob,
                feeCollector: feeCollector,
                sweepCollector: sweepCollector,
                checkpointRewarder: address(checkpointRewarder),
                defaultPausers: defaults,
                checkpointDurationResolution: 1 hours,
                minCheckpointDuration: 8 hours,
                maxCheckpointDuration: 1 days,
                minPositionDuration: 7 days,
                maxPositionDuration: 10 * 365 days,
                minCircuitBreakerDelta: 0.15e18,
                // NOTE: This is a high max circuit breaker delta to ensure that
                // trading during tests isn't impeded by the circuit breaker.
                maxCircuitBreakerDelta: 2e18,
                minFixedAPR: 0.001e18,
                maxFixedAPR: 0.5e18,
                minTimeStretchAPR: 0.005e18,
                maxTimeStretchAPR: 0.5e18,
                minFees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                }),
                maxFees: IHyperdrive.Fees({
                    curve: ONE,
                    flat: ONE,
                    governanceLP: ONE,
                    governanceZombie: ONE
                }),
                linkerFactory: address(0xdeadbeef),
                linkerCodeHash: bytes32(uint256(0xdeadbabe))
            }),
            "HyperdriveFactory"
        );
        coreDeployer = address(new ERC4626HyperdriveCoreDeployer());
        target0Deployer = address(new ERC4626Target0Deployer());
        target1Deployer = address(new ERC4626Target1Deployer());
        target2Deployer = address(new ERC4626Target2Deployer());
        target3Deployer = address(new ERC4626Target3Deployer());
        target4Deployer = address(new ERC4626Target4Deployer());
        deployerCoordinator = address(
            new ERC4626HyperdriveDeployerCoordinator(
                "HyperdriveDeployerCoordinator",
                address(factory),
                coreDeployer,
                target0Deployer,
                target1Deployer,
                target2Deployer,
                target3Deployer,
                target4Deployer
            )
        );

        // Config changes required to support ERC4626 with the correct initial vault share price.
        IHyperdrive.PoolDeployConfig memory config = testDeployConfig(
            FIXED_RATE,
            POSITION_DURATION
        );
        config.governance = factory.hyperdriveGovernance();
        config.feeCollector = factory.feeCollector();
        config.linkerFactory = factory.linkerFactory();
        config.linkerCodeHash = factory.linkerCodeHash();
        config.timeStretch = 0;
        config.baseToken = underlyingToken;
        config.vaultSharesToken = token;
        config.minimumTransactionAmount = 1e6;
        config.minimumShareReserves = 1e6;
        uint256 contribution = 7_500e6;
        vm.stopPrank();
        vm.startPrank(alice);

        factory.addDeployerCoordinator(deployerCoordinator);

        // Set approval to allow initial contribution to factory.
        underlyingToken.approve(
            address(deployerCoordinator),
            type(uint256).max
        );

        // Deploy and set hyperdrive instance.
        for (
            uint256 i = 0;
            i <
            IHyperdriveDeployerCoordinator(deployerCoordinator)
                .getNumberOfTargets();
            i++
        ) {
            factory.deployTarget(
                bytes32(uint256(0xbeefbabe)),
                deployerCoordinator,
                config,
                new bytes(0),
                FIXED_RATE,
                FIXED_RATE,
                i,
                bytes32(uint256(0xdeadfade))
            );
        }
        hyperdrive = factory.deployAndInitialize(
            bytes32(uint256(0xbeefbabe)),
            deployerCoordinator,
            "Hyperdrive",
            config,
            new bytes(0),
            contribution,
            FIXED_RATE,
            FIXED_RATE,
            IHyperdrive.Options({
                asBase: true,
                destination: alice,
                extraData: new bytes(0)
            }),
            bytes32(uint256(0xdeadfade))
        );

        // Setup maximum approvals so transfers don't require further approval.
        underlyingToken.approve(address(hyperdrive), type(uint256).max);
        underlyingToken.approve(address(token), type(uint256).max);
        token.approve(address(hyperdrive), type(uint256).max);
        vm.stopPrank();

        // Start recording events.
        vm.recordLogs();
    }

    function advanceTimeWithYield(
        uint256 timeDelta,
        int256 variableRate
    ) public override {
        vm.warp(block.timestamp + timeDelta);
        (, int256 interest) = HyperdriveUtils.calculateCompoundInterest(
            underlyingToken.balanceOf(address(token)),
            variableRate,
            timeDelta
        );
        if (interest > 0) {
            ERC20Mintable(address(underlyingToken)).mint(
                address(token),
                uint256(interest)
            );
        } else if (interest < 0) {
            ERC20Mintable(address(underlyingToken)).burn(
                address(token),
                uint256(-interest)
            );
        }
    }
}
