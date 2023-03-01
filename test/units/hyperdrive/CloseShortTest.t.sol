// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

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

    function test_close_short_immediately() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, bondAmount);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Immediately close the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't end up with more base than he started with.
        assertGe(basePaid, baseProceeds);

        // Verify that the close long updates were correct.
        verifyCloseShort(
            poolInfoBefore,
            basePaid,
            baseProceeds,
            bondAmount,
            maturityTime
        );
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
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // Immediately close the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't end up with more base than he started with.
        assertGe(basePaid, baseProceeds);

        // Verify that the close long updates were correct.
        verifyCloseShort(
            poolInfoBefore,
            basePaid,
            baseProceeds,
            bondAmount,
            maturityTime
        );
    }

    function test_close_short_redeem() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, bondAmount);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // The term passes.
        vm.warp(block.timestamp + 365 days);

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't receive any base from closing the short.
        assertEq(baseProceeds, 0);

        // Verify that the close long updates were correct.
        verifyCloseShort(
            poolInfoBefore,
            basePaid,
            baseProceeds,
            bondAmount,
            maturityTime
        );
    }

    function test_close_short_redeem_negative_interest() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, bondAmount);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // The term passes.
        vm.warp(block.timestamp + 365 days);
        // Small loss
        hyperdrive.setSharePrice((getPoolInfo().sharePrice * 80) / 100);

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't receive any base from closing the short.
        assertEq(baseProceeds, 0);

        // Verify that the close long updates were correct.
        verifyCloseShort(
            poolInfoBefore,
            basePaid,
            baseProceeds,
            bondAmount,
            maturityTime
        );
    }

    function test_close_short_redeem_negative_interest_half_term() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, bondAmount);

        // Get the reserves before closing the long.
        PoolInfo memory poolInfoBefore = getPoolInfo();

        // The term passes.
        vm.warp(block.timestamp + (365 days) / 2);
        // Small loss
        hyperdrive.setSharePrice((getPoolInfo().sharePrice * 80) / 100);

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't receive any base from closing the short.
        assertEq(baseProceeds, 0);

        // Verify that the close long updates were correct.
        verifyCloseShort(
            poolInfoBefore,
            basePaid,
            baseProceeds,
            bondAmount,
            maturityTime
        );
    }

    function verifyCloseShort(
        PoolInfo memory poolInfoBefore,
        uint256 basePaid,
        uint256 baseProceeds,
        uint256 bondAmount,
        uint256 maturityTime
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

        // Verify that the reserves were updated according to flat+curve.
        // The bond adjustment should be equal to timeRemaining * bondAmount
        // because the bond update decays as the term progresses.
        PoolInfo memory poolInfoAfter = getPoolInfo();
        uint256 timeRemaining = calculateTimeRemaining(maturityTime);
        assertApproxEqAbs(
            poolInfoAfter.bondReserves,
            poolInfoBefore.bondReserves - timeRemaining.mulDown(bondAmount),
            1
        );

        // Verify that the other state was updated correctly.
        (
            ,
            uint256 checkpointLongBaseVolume,
            uint256 checkpointShortBaseVolume
        ) = hyperdrive.checkpoints(checkpointTime);
        assertApproxEqAbs(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves +
                (bondAmount + baseProceeds - basePaid).divDown(
                    poolInfoBefore.sharePrice
                ),
            // 10^-7
            poolInfoAfter.shareReserves.mulDown(1e11) // TODO: This error bar is too big. Analyze this.
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(poolInfoAfter.longBaseVolume, 0);
        assertEq(checkpointLongBaseVolume, 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding - bondAmount
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortBaseVolume, 0);
        assertEq(checkpointShortBaseVolume, 0);
    }
}
