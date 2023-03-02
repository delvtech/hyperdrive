// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import "../../../lib/forge-std/src/console2.sol";

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
        hyperdrive.openShort(0, type(uint256).max, bob, true);
    }

    function test_open_short_failure_extreme_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to short an extreme amount of bonds. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = getPoolInfo().shareReserves;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        vm.expectRevert(Errors.FixedPointMath_SubOverflow.selector);
        hyperdrive.openShort(baseAmount * 2, type(uint256).max, bob, true);
    }

    function test_open_short() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the short.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Short a small amount of bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, uint256 baseAmount) = openShort(bob, bondAmount);

        // Print the results.
        console2.log("maturityTime", maturityTime);
        console2.log("bondAmount:%s cents -> baseAmount:%s cents", bondAmount/1e16, baseAmount/1e16);
        console2.log("bondAmount:%s -> baseAmount:%s", bondAmount, baseAmount);

        // Verify the open short updates occurred correctly.
        verifyOpenShort(
            poolInfoBefore,
            contribution,
            baseAmount,
            bondAmount,
            maturityTime,
            apr
        );
    }

    function test_open_short_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the short.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Short a small amount of bonds.
        uint256 bondAmount = .1e18;
        (uint256 maturityTime, uint256 baseAmount) = openShort(bob, bondAmount);

        // Verify the open short updates occurred correctly.
        verifyOpenShort(
            poolInfoBefore,
            contribution,
            baseAmount,
            bondAmount,
            maturityTime,
            apr
        );
    }

    function verifyOpenShort(
        PoolInfo memory poolInfoBefore,
        uint256 contribution,
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 maturityTime,
        uint256 apr
    ) internal {
        uint256 checkpointTime = maturityTime - POSITION_DURATION;

        // Verify that Hyperdrive received the max loss and that Bob received
        // the short tokens.
        console2.log("baseToken.balanceOf(address(hyperdrive)):%s", baseToken.balanceOf(address(hyperdrive))/1e18);
        console2.log("contribution:%s", contribution/1e18);
        console2.log("baseAmount:%s", baseAmount/1e18);
        console2.log("contribution + baseAmount:%s", (contribution + baseAmount)/1e18);

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

        // Verify that the short didn't receive an APR higher than the pool's
        // APR.
        uint256 baseProceeds = bondAmount - baseAmount;
        uint256 realizedApr = calculateAPRFromRealizedPrice(
            baseProceeds,
            bondAmount,
            FixedPointMath.ONE_18
        );
        assertLt(apr, realizedApr);

        // Verify that the pool's APR didn't go down.

        // Verify that the reserves were updated correctly.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        (
            ,
            uint256 checkpointLongBaseVolume,
            uint256 checkpointShortBaseVolume
        ) = hyperdrive.checkpoints(checkpointTime);
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
        assertEq(checkpointLongBaseVolume, 0);
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
        assertEq(checkpointShortBaseVolume, baseProceeds);
    }
}
