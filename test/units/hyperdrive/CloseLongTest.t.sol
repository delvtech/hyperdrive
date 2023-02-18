// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "./HyperdriveTest.sol";

contract CloseLongTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_close_long_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = 10e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);

        // Attempt to close zero longs. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        hyperdrive.closeLong(maturityTime, 0, 0, bob);
    }

    function test_close_long_failure_invalid_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = 10e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);

        // Attempt to close too many longs. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 maturityTime = (block.timestamp - (block.timestamp % 1 days)) +
            365 days;
        uint256 bondAmount = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bob
        );
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.closeLong(maturityTime, bondAmount + 1, 0, bob);
    }

    function test_close_long_failure_invalid_timestamp() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = 10e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);

        // Attempt to use a timestamp greater than the maximum range.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.InvalidTimestamp.selector);
        hyperdrive.closeLong(uint256(type(uint248).max) + 1, 1, 0, bob);
    }

    function test_close_long_immediately() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = 10e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Immediately close the bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 checkpointTime = block.timestamp - (block.timestamp % 1 days);
        uint256 maturityTime = checkpointTime + 365 days;
        uint256 bondAmount = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bob
        );
        hyperdrive.closeLong(maturityTime, bondAmount, 0, bob);

        // Verify that all of Bob's bonds were burned and that he has
        // approximately as much base as he started with.
        uint256 baseProceeds = baseToken.balanceOf(bob);
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                bob
            ),
            0
        );
        // Verify that bob doesn't end up with more than he started with
        assertGe(baseAmount, baseProceeds);

        // Verify that the reserves were updated correctly. Since this trade
        // happens at the beginning of the term, the bond reserves should be
        // increased by the full amount.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves -
                baseProceeds.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(
            poolInfoAfter.bondReserves,
            poolInfoBefore.bondReserves + bondAmount
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding - bondAmount
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(poolInfoAfter.longBaseVolume, 0);
        assertEq(hyperdrive.longBaseVolumeCheckpoints(checkpointTime), 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortBaseVolume, 0);
        assertEq(hyperdrive.shortBaseVolumeCheckpoints(checkpointTime), 0);
    }

    function test_close_long_immediately_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = .01e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Immediately close the bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 checkpointTime = block.timestamp - (block.timestamp % 1 days);
        uint256 maturityTime = checkpointTime + 365 days;
        uint256 bondAmount = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bob
        );
        hyperdrive.closeLong(maturityTime, bondAmount, 0, bob);

        // Verify that all of Bob's bonds were burned and that he has
        // approximately as much base as he started with.
        uint256 baseProceeds = baseToken.balanceOf(bob);
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                bob
            ),
            0
        );
        // Verify that bob doesn't end up with more than he started with
        assertGe(baseAmount, baseProceeds);

        // Verify that the reserves were updated correctly. Since this trade
        // happens at the beginning of the term, the bond reserves should be
        // increased by the full amount.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves -
                baseProceeds.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(
            poolInfoAfter.bondReserves,
            poolInfoBefore.bondReserves + bondAmount
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding - bondAmount
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(poolInfoAfter.longBaseVolume, 0);
        assertEq(hyperdrive.longBaseVolumeCheckpoints(checkpointTime), 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortBaseVolume, 0);
        assertEq(hyperdrive.shortBaseVolumeCheckpoints(checkpointTime), 0);
    }

    // TODO: Clean up these tests.
    function test_close_long_redeem() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = 10e18;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, bob);
        uint256 checkpointTime = block.timestamp - (block.timestamp % 1 days);
        uint256 maturityTime = checkpointTime + 365 days;

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // The term passes.
        vm.warp(block.timestamp + 365 days);

        // Redeem the bonds
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bob
        );
        hyperdrive.closeLong(maturityTime, bondAmount, 0, bob);

        // Verify that all of Bob's bonds were burned and that he has
        // approximately as much base as he started with.
        uint256 baseProceeds = baseToken.balanceOf(bob);
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                bob
            ),
            0
        );
        assertEq(baseProceeds, bondAmount);

        // Verify that the reserves were updated correctly. Since this trade
        // is a redemption, there should be no changes to the bond reserves.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves -
                bondAmount.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding - bondAmount
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(poolInfoAfter.longBaseVolume, 0);
        assertEq(hyperdrive.longBaseVolumeCheckpoints(checkpointTime), 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortBaseVolume, 0);
        assertEq(hyperdrive.shortBaseVolumeCheckpoints(checkpointTime), 0);
    }
}
