// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "./HyperdriveTest.sol";

contract OpenLongTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_open_long_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to purchase bonds with zero base. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.openLong(0, 0, bob);
    }

    function test_open_long_failure_extreme_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to purchase more bonds than exist. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = hyperdrive.bondReserves();
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.openLong(baseAmount, 0, bob);
    }

    function test_open_long() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Open a long.
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, baseAmount);

        // Verify that the open long updated the state correctly.
        verifyOpenLong(
            poolInfoBefore,
            contribution,
            baseAmount,
            bondAmount,
            maturityTime,
            apr
        );
    }

    function test_open_long_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Purchase a small amount of bonds.
        uint256 baseAmount = .01e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, baseAmount);

        // Verify that the open long updated the state correctly.
        verifyOpenLong(
            poolInfoBefore,
            contribution,
            baseAmount,
            bondAmount,
            maturityTime,
            apr
        );
    }

    function verifyOpenLong(
        PoolInfo memory poolInfoBefore,
        uint256 contribution,
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 maturityTime,
        uint256 apr
    ) internal {
        uint256 checkpointTime = maturityTime - POSITION_DURATION;

        // Verify the base transfers.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            contribution + baseAmount
        );

        // Verify that opening a long doesn't make the APR go up.
        uint256 realizedApr = calculateAPRFromRealizedPrice(
            baseAmount,
            bondAmount,
            FixedPointMath.ONE_18
        );
        assertGt(apr, realizedApr);

        // Verify that the reserves were updated correctly.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves +
                baseAmount.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(
            poolInfoAfter.bondReserves,
            poolInfoBefore.bondReserves - bondAmount
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding + bondAmount
        );
        assertApproxEqAbs(
            poolInfoAfter.longAverageMaturityTime,
            maturityTime,
            1
        );
        assertEq(poolInfoAfter.longBaseVolume, baseAmount);
        assertEq(
            hyperdrive.longBaseVolumeCheckpoints(checkpointTime),
            baseAmount
        );
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortBaseVolume, 0);
        assertEq(hyperdrive.shortBaseVolumeCheckpoints(checkpointTime), 0);
    }
}
