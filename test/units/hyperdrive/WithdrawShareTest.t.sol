// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

contract RemoveLiquidityTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_redeem_withdraw_shares_fail_insufficient_shares() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Time passes and interest accrues.
        uint256 timeDelta = 0.5e18;
        uint256 timeAdvanced = POSITION_DURATION.mulDown(timeDelta);
        advanceTime(timeAdvanced, int256(apr));
        uint256 maturityTime = latestCheckpoint() + POSITION_DURATION;

        // Bob opens a long.
        uint256 bondAmount = 50_000_000e18;
        openShort(bob, bondAmount);

        // We add another LP [prevents div by zero when alice withdraws]
        addLiquidity(celine, contribution / 5);

        // Alice removes all of her liquidity.
        removeLiquidity(alice, lpShares);

        uint256 aliceWithdrawShares = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0),
            alice
        );

        // Ensure the withdraw shares are ready
        vm.warp(maturityTime);
        hyperdrive.checkpoint(maturityTime);

        // Alice tries to redeem her withdraw shares
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.redeemWithdrawalShares(
            aliceWithdrawShares + 1,
            0,
            alice,
            true
        );
        // Alice can redeem but doesn't meet the withdraw limit she sets
        (
            uint256 readyForWithdraw,
            uint256 marginPool,
            uint256 interestPool
        ) = hyperdrive.withdrawPool();
        uint256 sharePrice = getPoolInfo().sharePrice;
        vm.expectRevert(Errors.OutputLimit.selector);
        hyperdrive.redeemWithdrawalShares(
            readyForWithdraw,
            (marginPool + interestPool).mulDown(sharePrice) + 1,
            alice,
            true
        );
    }

    function test_redeem_withdraw_shares_short() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Time passes and interest accrues.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), int256(apr));
        uint256 maturityTime = latestCheckpoint() + POSITION_DURATION;

        // Bob opens a long.
        uint256 bondAmount = 50_000_000e18;
        (, uint256 bobBasePaid) = openShort(bob, bondAmount);

        // We add another LP [prevents div by zero when alice withdraws]
        uint256 celineShares = addLiquidity(celine, contribution / 5);

        // Alice removes all of her liquidity.
        removeLiquidity(alice, lpShares);

        // Pool checks
        PoolInfo memory poolInfo = getPoolInfo();

        // Ensure that Alice receives the right amount of withdrawal shares.
        (, , , uint256 shortBaseVolume) = hyperdrive.aggregates();
        uint256 withdrawSharesExpected = (shortBaseVolume)
            .divDown(poolInfo.sharePrice)
            .mulDivDown(lpShares, celineShares + lpShares);

        uint256 aliceWithdrawShares = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0),
            alice
        );
        assertApproxEqAbs(aliceWithdrawShares, withdrawSharesExpected, 1);

        vm.warp(maturityTime);

        hyperdrive.checkpoint(maturityTime);

        (
            uint256 readyToWithdraw,
            uint256 marginPool,
            uint256 interestPool
        ) = hyperdrive.withdrawPool();
        assertApproxEqAbs(
            readyToWithdraw,
            aliceWithdrawShares,
            (aliceWithdrawShares * 999999) / 1000000
        );
        aliceWithdrawShares = aliceWithdrawShares > readyToWithdraw
            ? readyToWithdraw
            : aliceWithdrawShares;

        // Redeem Alice LP shares
        hyperdrive.redeemWithdrawalShares(aliceWithdrawShares, 0, alice, true);

        // The initial contribution plus 2.5% interest from the first accumulation plus 5/6 of Bob's short
        // because celine provides the other 1/6th.
        uint256 estimatedOutcome;
        {
            // 2.5% interest accrued before Bob opened his long
            (uint256 aliceContribution, ) = hyperdrive
                .calculateCompoundInterest(
                    500_000_000e18,
                    0.05e18,
                    POSITION_DURATION.mulDown(0.5e18)
                );
            estimatedOutcome =
                aliceContribution +
                bobBasePaid.mulDivDown(5e18, 6e18);
        }
        // TODO - very large error bars here, 1 basis point off
        assertApproxEqAbs(
            baseToken.balanceOf(alice),
            estimatedOutcome,
            13_000e18
        );

        aliceWithdrawShares = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0),
            alice
        );
        // We allow a very small rounding error
        assertApproxEqAbs(aliceWithdrawShares, 0, 50000000);

        // Alice is the only LP withdrawing so the pool should be empty
        (readyToWithdraw, marginPool, interestPool) = hyperdrive.withdrawPool();
        assertEq(readyToWithdraw, 0);
        assertEq(marginPool, 0);
        assertEq(interestPool, 0);

        // Withdraw celine
        uint256 celineWithdraw = removeLiquidity(
            celine,
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, celine)
        );
        uint256 celineWithdrawShares = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0),
            celine
        );
        assertEq(celineWithdrawShares, 0);
        // TODO - Large basis point error, the error is because Alice earns about a basis point more than expected
        assertApproxEqAbs(
            celineWithdraw,
            100_000_000e18 + bobBasePaid / 6,
            baseToken.balanceOf(alice) - estimatedOutcome + 10
        );
    }

    function test_redeem_withdraw_shares_long() external {
        // Initialize the pool with a large amount of capital.
        uint256 lpShares = initialize(alice, 0.05e18, 500_000_000e18);

        // Time passes and interest accrues.
        advanceTime(POSITION_DURATION.mulDown(0.5e18), 0.05e18);

        // Bob opens a long.
        uint256 bobBasePaid = 50_000_000e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(
            bob,
            50_000_000e18
        );
        uint256 bobProfit = bondAmount - bobBasePaid;

        // We add another LP [prevents div by zero when alice withdraws]
        uint256 celineShares = addLiquidity(celine, 100_000_000e18);

        // Alice removes all of her liquidity.
        removeLiquidity(alice, lpShares);

        // Pool checks
        PoolInfo memory poolInfo = getPoolInfo();

        uint256 withdrawSharesExpected;
        uint256 aliceWithdrawShares;
        {
            // Ensure that Alice receives the right amount of withdrawal shares.
            (, uint256 longBaseVolume, , ) = hyperdrive.aggregates();
            (, , uint256 longsOutstanding, ) = hyperdrive.marketState();

            withdrawSharesExpected = (longsOutstanding - longBaseVolume)
                .divDown(poolInfo.sharePrice)
                .mulDivDown(lpShares, celineShares + lpShares);

            aliceWithdrawShares = hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0),
                alice
            );
        }
        assertEq(aliceWithdrawShares, withdrawSharesExpected);

        // Longs have a checkpoint open one checkpoint after they are created to protect LPs
        advanceTime(CHECKPOINT_DURATION, 0.05e18);
        hyperdrive.checkpoint(latestCheckpoint());

        advanceTime(POSITION_DURATION - CHECKPOINT_DURATION, 0.05e18);
        hyperdrive.checkpoint(maturityTime);

        (
            uint256 readyToWithdraw,
            uint256 marginPool,
            uint256 interestPool
        ) = hyperdrive.withdrawPool();

        assertApproxEqAbs(
            readyToWithdraw,
            aliceWithdrawShares,
            (aliceWithdrawShares * 999999) / 1000000
        );
        aliceWithdrawShares = aliceWithdrawShares > readyToWithdraw
            ? readyToWithdraw
            : aliceWithdrawShares;

        // Redeem Alice LP shares
        hyperdrive.redeemWithdrawalShares(aliceWithdrawShares, 0, alice, true);

        // The initial contribution plus 2.5% interest from the first accumulation minus 5/6 of the loss
        // from providing the interest on bob's long + 5/6 of the 2.5% interest from bob's long
        uint256 estimatedOutcomeAlice;
        {
            // 2.5% interest accrued before Bob opened his long
            (uint256 aliceContribution, ) = hyperdrive
                .calculateCompoundInterest(
                    500_000_000e18,
                    0.05e18,
                    POSITION_DURATION.mulDown(0.5e18)
                );
            (, int256 _bobInterest) = hyperdrive.calculateCompoundInterest(
                bondAmount,
                0.05e18,
                POSITION_DURATION
            );
            estimatedOutcomeAlice +=
                aliceContribution +
                uint256(_bobInterest).mulDivDown(5e18, 6e18) -
                ((bobProfit * 5) / 6);
        }

        // TODO - very large error bars here
        assertApproxEqAbs(
            baseToken.balanceOf(alice),
            estimatedOutcomeAlice,
            5000e18
        );

        aliceWithdrawShares = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0),
            alice
        );

        // We allow a very small rounding error
        assertApproxEqAbs(aliceWithdrawShares, 0, 20000000);

        // Alice is the only LP withdrawing so the pool should be empty
        (readyToWithdraw, marginPool, interestPool) = hyperdrive.withdrawPool();
        assertEq(readyToWithdraw, 0);
        assertEq(marginPool, 0);
        assertEq(interestPool, 0);

        // Withdraw celine
        uint256 celineWithdraw = removeLiquidity(
            celine,
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, celine)
        );
        {
            uint256 celineWithdrawShares = hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0),
                celine
            );
            assertEq(celineWithdrawShares, 0);
        }

        // Celine receives interest on her whole deposit because it remains in
        // the pool, minus the fixed rate owed to bob
        uint256 estimatedOutcomeCeline;
        {
            (uint256 celineContribution, ) = hyperdrive
                .calculateCompoundInterest(
                    100_000_000e18,
                    0.05e18,
                    POSITION_DURATION
                );
            (, int256 _bobInterest) = hyperdrive.calculateCompoundInterest(
                bondAmount,
                0.05e18,
                POSITION_DURATION
            );
            estimatedOutcomeCeline +=
                celineContribution +
                uint256(_bobInterest).divDown(6e18) -
                (bobProfit / 6);
        }

        // TODO - Large basis point error
        assertApproxEqAbs(celineWithdraw, estimatedOutcomeCeline, 15000e18);
    }
}
