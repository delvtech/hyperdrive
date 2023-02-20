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

        // Open a long position.
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, ) = openLong(hyperdrive, bob, baseAmount);

        // Attempt to close zero longs. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.closeLong(maturityTime, 0, 0, bob);
    }

    function test_close_long_failure_invalid_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a long position.
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(
            hyperdrive,
            bob,
            baseAmount
        );

        // Attempt to close too many longs. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.closeLong(maturityTime, bondAmount + 1, 0, bob);
    }

    function test_close_long_failure_invalid_timestamp() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a long position.
        uint256 baseAmount = 10e18;
        openLong(hyperdrive, bob, baseAmount);

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

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo(hyperdrive);

        // Immediately close the bonds.
        uint256 baseProceeds = closeLong(
            hyperdrive,
            bob,
            maturityTime,
            bondAmount
        );

        // Verify that Bob didn't receive more base than he put in.
        assertLe(baseProceeds, basePaid);

        // Verify that the close long updates were correct.
        verifyCloseLong(poolInfoBefore, baseProceeds, bondAmount, maturityTime);
    }

    function test_close_long_immediately_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a long position.
        uint256 basePaid = .01e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo(hyperdrive);

        // Immediately close the bonds.
        uint256 baseProceeds = closeLong(
            hyperdrive,
            bob,
            maturityTime,
            bondAmount
        );

        // Verify that Bob didn't receive more base than he put in.
        assertLe(baseProceeds, basePaid);

        // Verify that the close long updates were correct.
        verifyCloseLong(poolInfoBefore, baseProceeds, bondAmount, maturityTime);
    }

    function test_close_long_redeem() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo(hyperdrive);

        // The term passes.
        vm.warp(block.timestamp + POSITION_DURATION);

        // Redeem the bonds
        uint256 baseProceeds = closeLong(
            hyperdrive,
            bob,
            maturityTime,
            bondAmount
        );

        // Verify that Bob received base equal to the full bond amount.
        assertEq(baseProceeds, bondAmount);

        // Verify that the close long updates were correct.
        verifyCloseLong(poolInfoBefore, baseProceeds, bondAmount, maturityTime);
    }

    function verifyCloseLong(
        PoolInfo memory poolInfoBefore,
        uint256 baseProceeds,
        uint256 bondAmount,
        uint256 maturityTime
    ) internal {
        uint256 checkpointTime = maturityTime - POSITION_DURATION;

        // Verify that all of Bob's bonds were burned and that the base proceeds
        // are as expected.
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                bob
            ),
            0
        );

        // Verify that the bond reserves were updated according to flat+curve.
        // The adjustment should be equal to timeRemaining * bondAmount.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        uint256 timeRemaining = calculateTimeRemaining(maturityTime);
        assertEq(
            poolInfoAfter.bondReserves,
            poolInfoBefore.bondReserves + timeRemaining.mulDown(bondAmount)
        );

        // Verify that the other states were correct.
        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves -
                baseProceeds.divDown(poolInfoBefore.sharePrice)
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
}
