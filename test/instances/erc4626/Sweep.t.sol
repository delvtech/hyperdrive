// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626Hyperdrive } from "contracts/src/instances/erc4626/ERC4626Hyperdrive.sol";
import { ERC4626Target0 } from "contracts/src/instances/erc4626/ERC4626Target0.sol";
import { ERC4626Target1 } from "contracts/src/instances/erc4626/ERC4626Target1.sol";
import { ERC4626Target2 } from "contracts/src/instances/erc4626/ERC4626Target2.sol";
import { ERC4626Target3 } from "contracts/src/instances/erc4626/ERC4626Target3.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IERC4626Hyperdrive } from "contracts/src/interfaces/IERC4626Hyperdrive.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";
import { BaseTest } from "test/utils/BaseTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract SweepTest is BaseTest {
    ForwardingToken baseForwarder;
    ForwardingToken vaultForwarder;
    ERC20Mintable sweepable;

    IERC4626Hyperdrive hyperdrive;

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

        // Deploy the leaky vault with the leaky ERC20 as the asset. Then deploy
        // forwarding tokens for each of the targets.
        LeakyERC20 leakyBase = new LeakyERC20();
        LeakyVault leakyVault = new LeakyVault(leakyBase);
        baseForwarder = new ForwardingToken(address(leakyBase));
        vaultForwarder = new ForwardingToken(address(leakyVault));

        // Deploy Hyperdrive with the leaky vault as the backing vault.
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: IERC20(address(leakyBase)),
            linkerFactory: address(0),
            linkerCodeHash: bytes32(0),
            initialVaultSharePrice: ONE,
            minimumShareReserves: ONE,
            minimumTransactionAmount: 0.001e18,
            positionDuration: 365 days,
            checkpointDuration: 1 days,
            timeStretch: HyperdriveUtils.calculateTimeStretch(
                0.01e18,
                365 days
            ),
            governance: alice,
            feeCollector: bob,
            fees: IHyperdrive.Fees(0, 0, 0, 0)
        });
        vm.warp(3 * config.positionDuration);
        hyperdrive = IERC4626Hyperdrive(
            address(
                new ERC4626Hyperdrive(
                    config,
                    address(
                        new ERC4626Target0(
                            config,
                            IERC4626(address(leakyVault))
                        )
                    ),
                    address(
                        new ERC4626Target1(
                            config,
                            IERC4626(address(leakyVault))
                        )
                    ),
                    address(
                        new ERC4626Target2(
                            config,
                            IERC4626(address(leakyVault))
                        )
                    ),
                    address(
                        new ERC4626Target3(
                            config,
                            IERC4626(address(leakyVault))
                        )
                    ),
                    IERC4626(address(leakyVault))
                )
            )
        );

        // Initialize Hyperdrive. This ensures that Hyperdrive has vault tokens
        // to sweep.
        leakyBase.mint(alice, 100e18);
        leakyBase.approve(address(hyperdrive), 100e18);
        hyperdrive.initialize(
            100e18,
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
        vm.startPrank(celine);

        // Trying to call sweep with an invalid sweeper (an address that isn't
        // the fee collector or a pauser) should fail.
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        hyperdrive.sweep(IERC20(address(sweepable)));
    }

    function test_sweep_failure_direct_sweeps() external {
        vm.stopPrank();
        vm.startPrank(bob);

        // Trying to sweep the base token should fail.
        address baseToken = address(hyperdrive.baseToken());
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        hyperdrive.sweep(IERC20(baseToken));

        // Trying to sweep the vault token should fail.
        address vaultToken = address(hyperdrive.vault());
        vm.expectRevert(IHyperdrive.UnsupportedToken.selector);
        hyperdrive.sweep(IERC20(vaultToken));
    }

    function test_sweep_failure_indirect_sweeps() external {
        vm.stopPrank();
        vm.startPrank(bob);

        // Trying to sweep the base token via the forwarding token should fail.
        vm.expectRevert(IHyperdrive.SweepFailed.selector);
        hyperdrive.sweep(IERC20(address(baseForwarder)));

        // Trying to sweep the vault token via the forwarding token should fail.
        vm.expectRevert(IHyperdrive.SweepFailed.selector);
        hyperdrive.sweep(IERC20(address(vaultForwarder)));
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

contract LeakyVault is MockERC4626 {
    constructor(
        ERC20Mintable _asset
    ) MockERC4626(_asset, "Leaky Vault", "LEAK", 0, address(0), false) {}

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
    constructor() ERC20Mintable("Leaky ERC20", "LEAK", 0, address(0), false) {}

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
