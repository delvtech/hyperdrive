// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "./HyperdriveTest.sol";

contract OpenShortTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_open_short_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to short zero bonds. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.openShort(0, type(uint256).max, bob);
    }

    function test_open_short_failure_extreme_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to short an extreme amount of bonds. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = hyperdrive.shareReserves();
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        vm.expectRevert(Errors.FixedPointMath_SubOverflow.selector);
        hyperdrive.openShort(baseAmount * 2, type(uint256).max, bob);
    }

    function test_open_short() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the short.
        PoolInfo memory poolInfoBefore = getPoolInfo(hyperdrive);

        // Short a small amount of bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, uint256 baseAmount) = openShort(
            hyperdrive,
            bob,
            bondAmount
        );
        uint256 checkpointTime = maturityTime - POSITION_DURATION;

        // Verify that Hyperdrive received the max loss and that Bob received
        // the short tokens.
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            contribution + baseAmount
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                bob
            ),
            bondAmount
        );

        // Verify that opening a short doesn't cause the pool's APR to go down.
        uint256 baseProceeds = bondAmount - baseAmount;
        uint256 realizedApr = calculateAPRFromRealizedPrice(
            baseProceeds,
            bondAmount,
            maturityTime - block.timestamp,
            POSITION_DURATION
        );
        assertLt(apr, realizedApr);

        // Verify that the reserves were updated correctly.
        PoolInfo memory poolInfoAfter = getPoolInfo(hyperdrive);
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
            poolInfoBefore.longsOutstanding
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(poolInfoAfter.longBaseVolume, 0);
        assertEq(hyperdrive.longBaseVolumeCheckpoints(checkpointTime), 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding + bondAmount
        );
        assertApproxEqAbs(
            poolInfoAfter.shortAverageMaturityTime,
            maturityTime,
            1
        );
        assertEq(poolInfoAfter.shortBaseVolume, baseProceeds);
        assertEq(
            hyperdrive.shortBaseVolumeCheckpoints(checkpointTime),
            baseProceeds
        );
    }

    function test_open_short_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the short.
        PoolInfo memory poolInfoBefore = getPoolInfo(hyperdrive);

        // Short a small amount of bonds.
        uint256 bondAmount = .1e18;
        (uint256 maturityTime, uint256 baseAmount) = openShort(
            hyperdrive,
            bob,
            bondAmount
        );
        uint256 checkpointTime = maturityTime - POSITION_DURATION;

        // Verify that Hyperdrive received the max loss and that Bob received
        // the short tokens.
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            contribution + baseAmount
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                bob
            ),
            bondAmount
        );

        // Verify that opening a short doesn't cause the pool's APR to go down.
        uint256 baseProceeds = bondAmount - baseAmount;
        uint256 realizedApr = calculateAPRFromRealizedPrice(
            baseProceeds,
            bondAmount,
            maturityTime - block.timestamp,
            POSITION_DURATION
        );
        assertLt(apr, realizedApr);

        // Verify that the reserves were updated correctly.
        PoolInfo memory poolInfoAfter = getPoolInfo(hyperdrive);
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
            poolInfoBefore.longsOutstanding
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(poolInfoAfter.longBaseVolume, 0);
        assertEq(hyperdrive.longBaseVolumeCheckpoints(checkpointTime), 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding + bondAmount
        );
        assertApproxEqAbs(
            poolInfoAfter.shortAverageMaturityTime,
            maturityTime,
            1
        );
        assertEq(poolInfoAfter.shortBaseVolume, baseProceeds);
        assertEq(
            hyperdrive.shortBaseVolumeCheckpoints(checkpointTime),
            baseProceeds
        );
    }
}
