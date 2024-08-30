// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { ERC4626Hyperdrive } from "../../../contracts/src/instances/erc4626/ERC4626Hyperdrive.sol";
import { ERC4626Target0 } from "../../../contracts/src/instances/erc4626/ERC4626Target0.sol";
import { ERC4626Target1 } from "../../../contracts/src/instances/erc4626/ERC4626Target1.sol";
import { ERC4626Target2 } from "../../../contracts/src/instances/erc4626/ERC4626Target2.sol";
import { ERC4626Target3 } from "../../../contracts/src/instances/erc4626/ERC4626Target3.sol";
import { ERC4626Target4 } from "../../../contracts/src/instances/erc4626/ERC4626Target4.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../../contracts/src/interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveEvents } from "../../../contracts/src/interfaces/IHyperdriveEvents.sol";
import { IHyperdriveFactory } from "../../../contracts/src/interfaces/IHyperdriveFactory.sol";
import { ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "../../../contracts/test/MockERC4626.sol";
import { BaseTest } from "../../utils/BaseTest.sol";

contract SweepTest is BaseTest, IHyperdriveEvents {
    ForwardingToken baseForwarder;
    ForwardingToken vaultForwarder;
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

        // Deploy the leaky vault with the leaky ERC20 as the asset. Then deploy
        // forwarding tokens for each of the targets.
        LeakyERC20 leakyBase = new LeakyERC20();
        LeakyVault leakyVault = new LeakyVault(leakyBase);
        baseForwarder = new ForwardingToken(address(leakyBase));
        vaultForwarder = new ForwardingToken(address(leakyVault));

        // Deploy the Hyperdrive factory.
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: IERC20(address(leakyBase)),
            vaultSharesToken: IERC20(address(leakyVault)),
            linkerFactory: address(0),
            linkerCodeHash: bytes32(0),
            initialVaultSharePrice: ONE,
            minimumShareReserves: ONE,
            minimumTransactionAmount: 0.001e18,
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

        // Deploy Hyperdrive with the leaky vault as the backing vault.
        vm.warp(3 * config.positionDuration);
        hyperdrive = IHyperdrive(
            address(
                new ERC4626Hyperdrive(
                    "Hyperdrive",
                    config,
                    IHyperdriveAdminController(address(factory)),
                    address(
                        new ERC4626Target0(
                            config,
                            IHyperdriveAdminController(address(factory))
                        )
                    ),
                    address(
                        new ERC4626Target1(
                            config,
                            IHyperdriveAdminController(address(factory))
                        )
                    ),
                    address(
                        new ERC4626Target2(
                            config,
                            IHyperdriveAdminController(address(factory))
                        )
                    ),
                    address(
                        new ERC4626Target3(
                            config,
                            IHyperdriveAdminController(address(factory))
                        )
                    ),
                    address(
                        new ERC4626Target4(
                            config,
                            IHyperdriveAdminController(address(factory))
                        )
                    )
                )
            )
        );

        // Initialize Hyperdrive. This ensures that Hyperdrive has vault tokens
        // to sweep.
        leakyBase.mint(alice, 1_000e18);
        leakyBase.approve(address(hyperdrive), 1_000e18);
        hyperdrive.initialize(
            1_000e18,
            0.05e18,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Mint some base tokens to Hyperdrive so that there is
        // something to sweep.
        leakyBase.mint(address(hyperdrive), 100e18);

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

    function test_sweep_failure_direct_vaultToken() external {
        vm.stopPrank();
        vm.startPrank(celine);

        // Trying to sweep the vault token should fail.
        address vaultToken = address(hyperdrive.vaultSharesToken());
        vm.expectRevert(IHyperdrive.SweepFailed.selector);
        hyperdrive.sweep(IERC20(vaultToken));
    }

    function test_sweep_failure_indirect_vaultToken() external {
        vm.stopPrank();
        vm.startPrank(celine);

        // Trying to sweep the vault token via the forwarding token should fail.
        vm.expectRevert(IHyperdrive.SweepFailed.selector);
        hyperdrive.sweep(IERC20(address(vaultForwarder)));
    }

    function test_sweep_success_direct_baseToken() external {
        vm.stopPrank();
        vm.startPrank(celine);

        // Trying to sweep the base token should succeed since any lingering amount is a mistake.
        address baseToken = address(hyperdrive.baseToken());
        hyperdrive.sweep(IERC20(baseToken));
    }

    function test_sweep_success_indirect_baseToken() external {
        vm.stopPrank();
        vm.startPrank(celine);

        // Trying to sweep the base token should succeed since any lingering amount is a mistake.
        hyperdrive.sweep(IERC20(address(baseForwarder)));
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

contract LeakyVault is MockERC4626 {
    constructor(
        ERC20Mintable _asset
    )
        MockERC4626(
            _asset,
            "Leaky Vault",
            "LEAK",
            0,
            address(0),
            false,
            type(uint256).max
        )
    {}

    // This function allows other addresses to transfer tokens from a spender.
    // This is obviously insecure, but it's an easy way to expose a forwarding
    // token that can abuse this leaky transfer function. This gives us a way
    // to test the `sweep` function.
    function leakyTransferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }
}

contract LeakyERC20 is ERC20Mintable {
    constructor()
        ERC20Mintable(
            "Leaky ERC20",
            "LEAK",
            0,
            address(0),
            false,
            type(uint256).max
        )
    {}

    // This function allows other addresses to transfer tokens from a spender.
    // This is obviously insecure, but it's an easy way to expose a forwarding
    // token that can abuse this leaky transfer function. This gives us a way
    // to test the `sweep` function.
    function leakyTransferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

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
        return LeakyERC20(target).balanceOf(account);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return LeakyERC20(target).leakyTransferFrom(msg.sender, to, amount);
    }
}
