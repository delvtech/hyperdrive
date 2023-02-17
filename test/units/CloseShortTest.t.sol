// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "./HyperdriveTest.sol";

contract CloseShortTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_close_short_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short..
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = 10e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        hyperdrive.openShort(bondAmount, type(uint256).max, bob);

        // Attempt to close zero shorts. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        hyperdrive.closeShort(maturityTime, 0, 0, bob);
    }

    function test_close_short_failure_invalid_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = 10e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        hyperdrive.openShort(bondAmount, type(uint256).max, bob);

        // Attempt to close too many shorts. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.closeShort(maturityTime, bondAmount + 1, 0, bob);
    }

    function test_close_short_failure_invalid_timestamp() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = 10e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        hyperdrive.openShort(bondAmount, type(uint256).max, bob);

        // Attempt to use a timestamp greater than the maximum range.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.InvalidTimestamp.selector);
        hyperdrive.closeShort(uint256(type(uint248).max) + 1, 1, 0, bob);
    }

    function test_close_short_immediately() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = 10e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        hyperdrive.openShort(bondAmount, type(uint256).max, bob);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Immediately close the bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 checkpointTime = block.timestamp - (block.timestamp % 1 days);
        uint256 maturityTime = checkpointTime + 365 days;
        hyperdrive.closeShort(maturityTime, bondAmount, 0, bob);

        // Verify that all of Bob's bonds were burned and that he has
        // approximately as much base as he started with.
        uint256 baseBalanceAfter = baseToken.balanceOf(bob);
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                bob
            ),
            0
        );
        // Verify that bob doesn't end up with more base than he started with
        assertGe(bondAmount, baseBalanceAfter);

        // Verify that the reserves were updated correctly. Since this trade
        // happens at the beginning of the term, the bond reserves should be
        // increased by the full amount.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertApproxEqAbs(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves +
                baseBalanceAfter.divDown(poolInfoBefore.sharePrice),
            1e18
        );
        assertEq(
            poolInfoAfter.bondReserves,
            poolInfoBefore.bondReserves - bondAmount
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(poolInfoAfter.longBaseVolume, 0);
        assertEq(hyperdrive.longBaseVolumeCheckpoints(checkpointTime), 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding - bondAmount
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortBaseVolume, 0);
        assertEq(hyperdrive.shortBaseVolumeCheckpoints(checkpointTime), 0);
    }

    function test_close_short_immediately_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = .1e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        hyperdrive.openShort(bondAmount, type(uint256).max, bob);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Immediately close the bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 checkpointTime = block.timestamp - (block.timestamp % 1 days);
        uint256 maturityTime = checkpointTime + 365 days;
        hyperdrive.closeShort(maturityTime, bondAmount, 0, bob);

        // Verify that all of Bob's bonds were burned and that he has
        // approximately as much base as he started with.
        uint256 baseBalanceAfter = baseToken.balanceOf(bob);
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                bob
            ),
            0
        );
        // Verify that bob doesn't end up with more base than he started with
        assertGe(bondAmount, baseBalanceAfter);

        // Verify that the reserves were updated correctly. Since this trade
        // happens at the beginning of the term, the bond reserves should be
        // increased by the full amount.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertApproxEqAbs(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves +
                baseBalanceAfter.divDown(poolInfoBefore.sharePrice),
            1e18
        );
        assertEq(
            poolInfoAfter.bondReserves,
            poolInfoBefore.bondReserves - bondAmount
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(poolInfoAfter.longBaseVolume, 0);
        assertEq(hyperdrive.longBaseVolumeCheckpoints(checkpointTime), 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding - bondAmount
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortBaseVolume, 0);
        assertEq(hyperdrive.shortBaseVolumeCheckpoints(checkpointTime), 0);
    }

    // TODO: Clean up these tests.
    function test_close_short_redeem() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = 10e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        hyperdrive.openShort(bondAmount, type(uint256).max, bob);
        uint256 checkpointTime = block.timestamp - (block.timestamp % 1 days);
        uint256 maturityTime = checkpointTime + 365 days;

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // The term passes.
        vm.warp(block.timestamp + 365 days);

        // Get the base balance before closing the short.
        uint256 baseBalanceBefore = baseToken.balanceOf(bob);

        // Redeem the bonds
        vm.stopPrank();
        vm.startPrank(bob);
        hyperdrive.closeShort(maturityTime, bondAmount, 0, bob);

        // TODO: Investigate this more to see if there are any irregularities
        // like there are with the long redemption test.
        //
        // Verify that all of Bob's bonds were burned and that he has
        // approximately as much base as he started with.
        uint256 baseBalanceAfter = baseToken.balanceOf(bob);
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                bob
            ),
            0
        );
        assertEq(baseBalanceAfter, baseBalanceBefore);

        // Verify that the reserves were updated correctly. Since this trade
        // is a redemption, there should be no changes to the bond reserves.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves +
                bondAmount.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(poolInfoAfter.longBaseVolume, 0);
        assertEq(hyperdrive.longBaseVolumeCheckpoints(checkpointTime), 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding - bondAmount
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortBaseVolume, 0);
        assertEq(hyperdrive.shortBaseVolumeCheckpoints(checkpointTime), 0);
    }
}
