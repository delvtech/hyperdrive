// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { StETHHyperdrive } from "../../../contracts/src/instances/steth/StETHHyperdrive.sol";
import { StETHTarget0 } from "../../../contracts/src/instances/steth/StETHTarget0.sol";
import { StETHTarget1 } from "../../../contracts/src/instances/steth/StETHTarget1.sol";
import { StETHTarget2 } from "../../../contracts/src/instances/steth/StETHTarget2.sol";
import { StETHTarget3 } from "../../../contracts/src/instances/steth/StETHTarget3.sol";
import { StETHTarget4 } from "../../../contracts/src/instances/steth/StETHTarget4.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdriveAdminController } from "../../../contracts/src/interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveEvents } from "../../../contracts/src/interfaces/IHyperdriveEvents.sol";
import { IHyperdriveFactory } from "../../../contracts/src/interfaces/IHyperdriveFactory.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { MockLido } from "../../../contracts/test/MockLido.sol";
import { BaseTest } from "../../utils/BaseTest.sol";

contract SweepTest is BaseTest, IHyperdriveEvents {
    string internal constant NAME = "Hyperdrive";

    ForwardingToken lidoForwarder;
    ERC20Mintable sweepable;

    IHyperdrive hyperdrive;
    IHyperdriveFactory internal factory;

    function setUp() public override {
        super.setUp();

        // We'll use Alice to deploy the contracts.
        vm.startPrank(alice);

        // Deploy the sweepable ERC20.
        sweepable = new ERC20Mintable(
            "Sweepable",
            "SWEEP",
            18,
            address(0),
            false,
            type(uint256).max
        );

        // Deploy the leaky lido instance. Then deploy forwarding tokens for
        // each of the targets. Add some ETH to the leaky lido instance to
        // ensure that it has a well-defined share price.
        LeakyLido leakyLido = new LeakyLido();
        lidoForwarder = new ForwardingToken(address(leakyLido));
        leakyLido.submit{ value: 1e18 }(address(0));

        // Deploy the Hyperdrive factory.
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: IERC20(address(ETH)),
            vaultSharesToken: IERC20(address(leakyLido)),
            linkerFactory: address(0),
            linkerCodeHash: bytes32(0),
            initialVaultSharePrice: ONE,
            minimumShareReserves: 1e15,
            minimumTransactionAmount: 1e15,
            circuitBreakerDelta: 1e18,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: HyperdriveMath.calculateTimeStretch(0.01e18, 365 days),
            governance: alice,
            feeCollector: bob,
            sweepCollector: celine,
            checkpointRewarder: address(0),
            fees: IHyperdrive.Fees(0, 0, 0, 0)
        });
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

        // Deploy Hyperdrive with the leaky lido.
        vm.warp(3 * config.positionDuration);
        hyperdrive = IHyperdrive(
            address(
                new StETHHyperdrive(
                    NAME,
                    config,
                    IHyperdriveAdminController(address(factory)),
                    address(
                        new StETHTarget0(
                            config,
                            IHyperdriveAdminController(address(factory))
                        )
                    ),
                    address(
                        new StETHTarget1(
                            config,
                            IHyperdriveAdminController(address(factory))
                        )
                    ),
                    address(
                        new StETHTarget2(
                            config,
                            IHyperdriveAdminController(address(factory))
                        )
                    ),
                    address(
                        new StETHTarget3(
                            config,
                            IHyperdriveAdminController(address(factory))
                        )
                    ),
                    address(
                        new StETHTarget4(
                            config,
                            IHyperdriveAdminController(address(factory))
                        )
                    )
                )
            )
        );

        // Initialize Hyperdrive. This ensures that Hyperdrive has vault tokens
        // to sweep.
        hyperdrive.initialize{ value: 100e18 }(
            100e18,
            0.05e18,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Mint some of the sweepable tokens to Hyperdrive.
        sweepable.mint(address(hyperdrive), 100e18);
    }

    function test_sweep_failure_invalid_sweeper() external {
        vm.stopPrank();
        vm.startPrank(bob);

        // Trying to call sweep with an invalid sweeper (an address that isn't
        // the fee collector or a pauser) should fail.
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        hyperdrive.sweep(IERC20(address(sweepable)));
    }

    function test_sweep_failure_direct_sweeps() external {
        vm.stopPrank();
        vm.startPrank(celine);

        // Trying to sweep the stETH token should fail.
        address lido = hyperdrive.vaultSharesToken();
        vm.expectRevert(IHyperdrive.SweepFailed.selector);
        hyperdrive.sweep(IERC20(lido));
    }

    function test_sweep_failure_indirect_sweeps() external {
        vm.stopPrank();
        vm.startPrank(celine);

        // Trying to sweep the stETH via the forwarding token should fail.
        vm.expectRevert(IHyperdrive.SweepFailed.selector);
        hyperdrive.sweep(IERC20(address(lidoForwarder)));
    }

    function test_sweep_success_sweepCollector() external {
        // The sweep collector can sweep a sweepable token.
        vm.stopPrank();
        vm.startPrank(celine);
        uint256 sweepableBalance = sweepable.balanceOf(address(hyperdrive));
        vm.expectEmit(true, true, true, true);
        emit Sweep(
            hyperdrive.getPoolConfig().sweepCollector,
            address(sweepable)
        );
        hyperdrive.sweep(IERC20(address(sweepable)));

        // Ensure that the tokens were successfully swept to the sweep
        // collector.
        assertEq(sweepable.balanceOf(address(hyperdrive)), 0);
        assertEq(
            sweepable.balanceOf(hyperdrive.getPoolConfig().sweepCollector),
            sweepableBalance
        );
    }

    function test_sweep_success_pauser() external {
        // Set up Celine as a pauser.
        vm.stopPrank();
        vm.startPrank(alice);
        hyperdrive.setPauser(celine, true);

        // A pauser can sweep a sweepable token.
        vm.stopPrank();
        vm.startPrank(celine);
        uint256 sweepableBalance = sweepable.balanceOf(address(hyperdrive));
        vm.expectEmit(true, true, true, true);
        emit Sweep(
            hyperdrive.getPoolConfig().sweepCollector,
            address(sweepable)
        );
        hyperdrive.sweep(IERC20(address(sweepable)));

        // Ensure that the tokens were successfully swept to the sweep
        // collector.
        assertEq(sweepable.balanceOf(address(hyperdrive)), 0);
        assertEq(
            sweepable.balanceOf(hyperdrive.getPoolConfig().sweepCollector),
            sweepableBalance
        );
    }

    function test_sweep_success_governance() external {
        // Governance can sweep a sweepable token.
        vm.stopPrank();
        vm.startPrank(hyperdrive.getPoolConfig().governance);
        uint256 sweepableBalance = sweepable.balanceOf(address(hyperdrive));
        vm.expectEmit(true, true, true, true);
        emit Sweep(
            hyperdrive.getPoolConfig().sweepCollector,
            address(sweepable)
        );
        hyperdrive.sweep(IERC20(address(sweepable)));

        // Ensure that the tokens were successfully swept to the sweep
        // collector.
        assertEq(sweepable.balanceOf(address(hyperdrive)), 0);
        assertEq(
            sweepable.balanceOf(hyperdrive.getPoolConfig().sweepCollector),
            sweepableBalance
        );
    }
}

contract LeakyLido is MockLido {
    constructor() MockLido(0, address(0), false, type(uint256).max) {}

    // This function allows other addresses to transfer tokens from a spender.
    // This is obviously insecure, but it's an easy way to expose a forwarding
    // token that can abuse this leaky transfer function. This gives us a way
    // to test the `sweep` function.
    function leakyTransferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        // Transfer the shares.
        uint256 sharesAmount = getSharesByPooledEth(amount);
        sharesOf[from] -= sharesAmount;
        sharesOf[to] += sharesAmount;

        // Emit an event.
        emit Transfer(from, to, amount);

        return true;
    }
}

contract ForwardingToken {
    address internal target;

    constructor(address _target) {
        target = _target;
    }

    function balanceOf(address account) external view returns (uint256) {
        return LeakyLido(target).balanceOf(account);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return LeakyLido(target).leakyTransferFrom(msg.sender, to, amount);
    }
}
