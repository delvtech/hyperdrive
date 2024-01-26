// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { StETHHyperdrive } from "contracts/src/instances/steth/StETHHyperdrive.sol";
import { StETHTarget0 } from "contracts/src/instances/steth/StETHTarget0.sol";
import { StETHTarget1 } from "contracts/src/instances/steth/StETHTarget1.sol";
import { StETHTarget2 } from "contracts/src/instances/steth/StETHTarget2.sol";
import { StETHTarget3 } from "contracts/src/instances/steth/StETHTarget3.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { IStETHHyperdrive } from "contracts/src/interfaces/IStETHHyperdrive.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockLido } from "contracts/test/MockLido.sol";
import { BaseTest } from "test/utils/BaseTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { ETH } from "test/utils/Constants.sol";

contract SweepTest is BaseTest {
    ForwardingToken lidoForwarder;
    ERC20Mintable sweepable;

    IStETHHyperdrive hyperdrive;

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
            false
        );

        // Deploy the leaky lido instance. Then deploy forwarding tokens for
        // each of the targets. Add some ETH to the leaky lido instance to
        // ensure that it has a well-defined share price.
        LeakyLido leakyLido = new LeakyLido();
        lidoForwarder = new ForwardingToken(address(leakyLido));
        leakyLido.submit{ value: 1e18 }(address(0));

        // Deploy Hyperdrive with the leaky lido.
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: IERC20(address(ETH)),
            linkerFactory: address(0),
            linkerCodeHash: bytes32(0),
            initialVaultSharePrice: ONE,
            minimumShareReserves: 1e15,
            minimumTransactionAmount: 1e15,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: HyperdriveMath.calculateTimeStretch(0.01e18, 365 days),
            governance: alice,
            feeCollector: bob,
            fees: IHyperdrive.Fees(0, 0, 0, 0)
        });
        vm.warp(3 * config.positionDuration);
        hyperdrive = IStETHHyperdrive(
            address(
                new StETHHyperdrive(
                    config,
                    address(
                        new StETHTarget0(config, ILido(address(leakyLido)))
                    ),
                    address(
                        new StETHTarget1(config, ILido(address(leakyLido)))
                    ),
                    address(
                        new StETHTarget2(config, ILido(address(leakyLido)))
                    ),
                    address(
                        new StETHTarget3(config, ILido(address(leakyLido)))
                    ),
                    ILido(address(leakyLido))
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
        vm.startPrank(celine);

        // Trying to call sweep with an invalid sweeper (an address that isn't
        // the fee collector or a pauser) should fail.
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        hyperdrive.sweep(IERC20(address(sweepable)));
    }

    function test_sweep_failure_direct_sweeps() external {
        vm.stopPrank();
        vm.startPrank(bob);

        // Trying to sweep the stETH token should fail.
        address lido = address(hyperdrive.lido());
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        hyperdrive.sweep(IERC20(lido));
    }

    function test_sweep_failure_indirect_sweeps() external {
        vm.stopPrank();
        vm.startPrank(bob);

        // Trying to sweep the stETH via the forwarding token should fail.
        vm.expectRevert(IHyperdrive.SweepFailed.selector);
        hyperdrive.sweep(IERC20(address(lidoForwarder)));
    }

    function test_sweep_success_feeCollector() external {
        // The fee collector can sweep a sweepable token.
        vm.stopPrank();
        vm.startPrank(bob);
        hyperdrive.sweep(IERC20(address(sweepable)));
    }

    function test_sweep_success_pauser() external {
        // Set up Celine as a pauser.
        vm.stopPrank();
        vm.startPrank(alice);
        hyperdrive.setPauser(celine, true);

        // A pauser can sweep a sweepable token.
        vm.stopPrank();
        vm.startPrank(celine);
        hyperdrive.sweep(IERC20(address(sweepable)));
    }
}

contract LeakyLido is MockLido {
    constructor() MockLido(0, address(0), false) {}

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
        return LeakyLido(target).balanceOf(account);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return LeakyLido(target).leakyTransferFrom(msg.sender, to, amount);
    }
}
