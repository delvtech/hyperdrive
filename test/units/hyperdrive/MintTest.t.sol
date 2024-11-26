// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

// FIXME
import { console2 as console } from "forge-std/console2.sol";

import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

// FIXME: Add full Natspec.
//
// FIXME: Add all of the failure tests.
//
// FIXME: Add assertions that show that:
//
// - The governance fees were paid.
// - The flat fee of the short was paid.
// - Variable interest was pre-paid.
// - The correct amount of bonds were minted.
//
// To make this test better, we can work backward from the bond amount to the
// full calculation.
//
// This should all contribute to ensuring solvency.
//
// FIXME: Think about what other tests we need once we have this function.
contract MintTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    /// @dev Sets up the harness and deploys and initializes a pool with fees.
    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();

        // Deploy and initialize a pool with fees.
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.fees.curve = 0.01e18;
        config.fees.flat = 0.0005e18;
        config.fees.governanceLP = 0.15e18;
        deploy(alice, config);
        initialize(alice, 0.05e18, 100_000e18);
    }

    /// @dev Ensures that minting fails when the amount is zero.
    function test_mint_failure_zero_amount() external {
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.MinimumTransactionAmount.selector);
        hyperdrive.mint(
            0,
            0,
            IHyperdrive.PairOptions({
                longDestination: bob,
                shortDestination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that minting fails when the vault share price is lower than
    ///      the minimum vault share price.
    function test_mint_failure_minVaultSharePrice() external {
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = 10e18;
        baseToken.mint(bob, basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        uint256 minVaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice *
            2;
        vm.expectRevert(IHyperdrive.MinimumSharePrice.selector);
        hyperdrive.mint(
            basePaid,
            minVaultSharePrice,
            IHyperdrive.PairOptions({
                longDestination: bob,
                shortDestination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that minting fails when ether is sent to the contract.
    function test_mint_failure_not_payable() external {
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = 10e18;
        baseToken.mint(bob, basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.mint{ value: 1 }(
            basePaid,
            0,
            IHyperdrive.PairOptions({
                longDestination: bob,
                shortDestination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that minting fails when the long destination is the zero
    ///      address.
    function test_mint_failure_long_destination_zero_address() external {
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = 10e18;
        baseToken.mint(bob, basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        vm.expectRevert(IHyperdrive.RestrictedZeroAddress.selector);
        hyperdrive.mint(
            basePaid,
            0,
            IHyperdrive.PairOptions({
                longDestination: address(0),
                shortDestination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that minting fails when the short destination is the zero
    ///      address.
    function test_mint_failure_short_destination_zero_address() external {
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = 10e18;
        baseToken.mint(bob, basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        vm.expectRevert(IHyperdrive.RestrictedZeroAddress.selector);
        hyperdrive.mint(
            basePaid,
            0,
            IHyperdrive.PairOptions({
                longDestination: bob,
                shortDestination: address(0),
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    /// @dev Ensures that minting fails when the pool is paused.
    function test_mint_failure_pause() external {
        pause(true);
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = 10e18;
        baseToken.mint(bob, basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        vm.expectRevert(IHyperdrive.PoolIsPaused.selector);
        hyperdrive.mint(
            basePaid,
            0,
            IHyperdrive.PairOptions({
                longDestination: bob,
                shortDestination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
        pause(false);
    }

    // FIXME: This case would be better if there was actually pre-paid interest.
    //
    /// @dev Ensures that minting performs correctly when it succeeds.
    function test_mint_success() external {
        // Mint some base tokens to Alice and approve Hyperdrive.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 baseAmount = 100_000e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);

        // Get some data before minting.
        uint256 maturityTime = hyperdrive.latestCheckpoint() +
            hyperdrive.getPoolConfig().positionDuration;
        uint256 idleBefore = hyperdrive.idle();
        uint256 kBefore = hyperdrive.k();
        uint256 spotPriceBefore = hyperdrive.calculateSpotPrice();
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(address(alice));
        uint256 aliceLongBalanceBefore = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            alice
        );
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );
        uint256 governanceFeesAccruedBefore = hyperdrive
            .getUncollectedGovernanceFees();

        // Ensure that Alice can successfully mint.
        vm.stopPrank();
        vm.startPrank(alice);
        (uint256 maturityTime_, uint256 bondAmount) = hyperdrive.mint(
            baseAmount,
            0,
            IHyperdrive.PairOptions({
                longDestination: alice,
                shortDestination: alice,
                asBase: true,
                extraData: ""
            })
        );
        assertEq(maturityTime_, maturityTime);

        // Verify that the balances increased and decreased by the right amounts.
        assertEq(
            baseToken.balanceOf(alice),
            aliceBaseBalanceBefore - baseAmount
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                alice
            ),
            aliceLongBalanceBefore + bondAmount
        );
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdriveBaseBalanceBefore + baseAmount
        );

        // Verify that idle, spot price, and pool depth are all
        // unchanged.
        assertEq(hyperdrive.idle(), idleBefore);
        assertEq(hyperdrive.calculateSpotPrice(), spotPriceBefore);
        assertEq(hyperdrive.k(), kBefore);

        // Ensure that the governance fees accrued increased by the right amount.
        assertEq(
            hyperdrive.getUncollectedGovernanceFees(),
            governanceFeesAccruedBefore +
                2 *
                bondAmount
                    .mulDown(hyperdrive.getPoolConfig().fees.flat)
                    .mulDown(hyperdrive.getPoolConfig().fees.governanceLP)
        );

        // FIXME: This is good, but we need test cases that verify that this
        // interoperates with the rest of the Hyperdrive system.
        //
        // Ensure that the base amount is the bond amount plus the prepaid
        // variable interest plus the governance fees plus the prepaid flat fee.
        uint256 openVaultSharePrice = hyperdrive
            .getCheckpoint(hyperdrive.latestCheckpoint())
            .vaultSharePrice;
        uint256 requiredBaseAmount = bondAmount +
            bondAmount.mulDivDown(
                hyperdrive.getPoolInfo().vaultSharePrice - openVaultSharePrice,
                openVaultSharePrice
            ) +
            bondAmount.mulDown(hyperdrive.getPoolConfig().fees.flat) +
            2 *
            bondAmount.mulDown(hyperdrive.getPoolConfig().fees.flat).mulDown(
                hyperdrive.getPoolConfig().fees.governanceLP
            );
        assertGt(baseAmount, requiredBaseAmount);
        assertApproxEqAbs(baseAmount, requiredBaseAmount, 2);

        // FIXME: Verify the event.
    }

    // FIXME: We can add more cases for minting success.

    // FIXME
    function _verifyMint() internal view {
        // FIXME
    }

    // FIXME
    // function verifyMintEvent() internal {
    //     VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
    //         Mint.selector
    //     );
    //     assertEq(logs.length, 1);
    //     VmSafe.Log memory log = logs[0];
    //     assertEq(address(uint160(uint256(log.topics[1]))), destination);
    // }
}
