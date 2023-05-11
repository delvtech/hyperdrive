// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";

contract CloseShortTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_close_short_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // Attempt to close zero shorts. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.closeShort(maturityTime, 0, 0, bob, true);
    }

    function test_close_short_failure_invalid_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // Attempt to close too many shorts. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.closeShort(maturityTime, bondAmount + 1, 0, bob, true);
    }

    function test_close_short_failure_invalid_timestamp() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short.
        uint256 bondAmount = 10e18;
        openShort(bob, bondAmount);

        // Attempt to use a timestamp greater than the maximum range.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.InvalidTimestamp.selector);
        hyperdrive.closeShort(uint256(type(uint248).max) + 1, 1, 0, bob, true);
    }

    function test_close_short_immediately_with_regular_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, bondAmount);

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Immediately close the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't end up with more base than he started with.
        assertGe(basePaid, baseProceeds);

        // Verify that the close long updates were correct.
        verifyCloseShort(poolInfoBefore, bondAmount, maturityTime, false);
    }

    function test_close_short_immediately_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = .1e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, bondAmount);

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Immediately close the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't end up with more base than he started with.
        assertGe(basePaid, baseProceeds);

        // Verify that the close long updates were correct.
        verifyCloseShort(poolInfoBefore, bondAmount, maturityTime, false);
    }

    // This stress tests the aggregate accounting by making the bond amount of
    // the second trade is off by 1 wei.
    function test_close_short_dust_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short position.
        uint256 shortAmount = 10_000_000e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Immediately close the bonds. We close the long in two transactions
        // to ensure that the close long function can handle small input amounts.
        uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount / 2);
        baseProceeds += closeShort(bob, maturityTime, shortAmount / 2 - 1);

        // Verify that Bob doesn't end up with more base than he started with.
        assertGe(basePaid, baseProceeds);

        // Ensure that the average maturity time was updated correctly.
        assertEq(
            hyperdrive.getPoolInfo().shortAverageMaturityTime,
            maturityTime * 1e18
        );
    }

    function test_close_short_redeem_at_maturity_zero_variable_interest()
        external
    {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // The term passes.
        vm.warp(block.timestamp + 365 days);

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't receive any base from closing the short.
        assertEq(baseProceeds, 0);

        // Verify that the close long updates were correct.
        verifyCloseShort(poolInfoBefore, bondAmount, maturityTime, false);
    }

    function test_close_short_redeem_negative_interest() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // The term passes.
        advanceTime(POSITION_DURATION, -0.2e18);

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't receive any base from closing the short.
        assertEq(baseProceeds, 0);

        // Verify that the close long updates were correct.
        verifyCloseShort(poolInfoBefore, bondAmount, maturityTime, false);
    }

    function test_close_short_redeem_negative_interest_half_term() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // The term passes and shares lose value
        advanceTime(POSITION_DURATION.mulDown(0.5e18), -0.2e18);

        // Get the reserves before closing the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't receive any base from closing the short.
        assertEq(baseProceeds, 0);

        // Verify that the close long updates were correct.
        verifyCloseShort(poolInfoBefore, bondAmount, maturityTime, false);
    }

    function test_close_short_negative_interest_at_close() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // The term passes and shares lose value
        advanceTime(POSITION_DURATION, -0.2e18);

        // A checkpoint is created to lock in the close price.
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // Another term passes and positive interest accrues.
        advanceTime(POSITION_DURATION, 0.5e18);

        // Get the reserves before closing the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't receive any base from closing the short.
        assertEq(baseProceeds, 0);

        // Verify that the close long updates were correct.
        verifyCloseShort(poolInfoBefore, bondAmount, maturityTime, true);
    }

    function test_close_short_max_loss() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 1000e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, bondAmount);

        // Advance and shares accrue 0% interest throughout the duration
        advanceTime(POSITION_DURATION, 0);
        assertEq(block.timestamp, maturityTime);

        // Get the reserves before closing the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Should be near 100% of a loss
        assertApproxEqAbs(
            basePaid.sub(baseProceeds).divDown(basePaid),
            1e18,
            1e15 // TODO Large tolerance?
        );

        // Verify that the close short updates were correct.
        verifyCloseShort(poolInfoBefore, bondAmount, maturityTime, false);
    }

    function verifyCloseShort(
        IHyperdrive.PoolInfo memory poolInfoBefore,
        uint256 bondAmount,
        uint256 maturityTime,
        bool wasCheckpointed
    ) internal {
        uint256 checkpointTime = maturityTime - POSITION_DURATION;

        // Verify that all of Bob's shorts were burned.
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

        // Retrieve the pool info after the trade.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
            checkpointTime
        );

        // Verify that the other state was updated correctly.
        uint256 timeRemaining = HyperdriveUtils.calculateTimeRemaining(
            hyperdrive,
            maturityTime
        );
        if (wasCheckpointed) {
            assertEq(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);
            assertEq(
                poolInfoAfter.shortsOutstanding,
                poolInfoBefore.shortsOutstanding
            );
        } else {
            // TODO: Re-evaluate this. This is obviously correct; however, it may
            // be better to use HyperdriveMath or find an approximation so that we
            // aren't repeating ourselves.
            uint256 expectedShareReserves = poolInfoBefore.shareReserves +
                bondAmount.mulDivDown(
                    FixedPointMath.ONE_18 - timeRemaining,
                    poolInfoBefore.sharePrice
                ) +
                YieldSpaceMath.calculateSharesInGivenBondsOut(
                    poolInfoBefore.shareReserves,
                    poolInfoBefore.bondReserves,
                    bondAmount.mulDown(timeRemaining),
                    FixedPointMath.ONE_18 -
                        hyperdrive.getPoolConfig().timeStretch,
                    poolInfoBefore.sharePrice,
                    hyperdrive.getPoolConfig().initialSharePrice
                );
            assertApproxEqAbs(
                poolInfoAfter.shareReserves,
                expectedShareReserves,
                1e10
            );
            assertEq(
                poolInfoAfter.shortsOutstanding,
                poolInfoBefore.shortsOutstanding - bondAmount
            );
        }
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortBaseVolume, 0);
        assertEq(checkpoint.shortBaseVolume, 0);

        // TODO: Figure out how to test for this.
        //
        // Ensure that the bond reserves were updated to have the correct APR.
        // Due to the way that the flat part of the trade is applied, the bond
        // reserve updates may not exactly correspond to the amount of bonds
        // transferred; however, the pool's APR should be identical to the APR
        // that the bond amount transfer implies. The bond adjustment should be
        // equal to timeRemaining * bondAmount because the bond update decays as
        // the term progresses.
        // uint256 timeRemaining = calculateTimeRemaining(maturityTime);
        // assertApproxEqAbs(
        //     calculateAPRFromReserves(),
        //     HyperdriveMath.calculateAPRFromReserves(
        //         poolInfoAfter.shareReserves,
        //         poolInfoBefore.bondReserves - timeRemaining.mulDown(bondAmount),
        //         poolInfoAfter.lpTotalSupply,
        //         INITIAL_SHARE_PRICE,
        //         POSITION_DURATION,
        //         hyperdrive.timeStretch()
        //     ),
        //     5
        // );
    }
}
