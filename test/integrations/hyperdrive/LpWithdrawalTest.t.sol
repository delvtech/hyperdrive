// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";

// TODO: Some scenarios that we need to test.
//
// - [ ] Short trade closed immediately.
// - [ ] Short trade closed at redemption.
// - [ ] A mixture of long and short trades.
// - [ ] LPs with different long and short weightings.
// - [ ] Cases where interest accrues before and after
contract LpWithdrawalTest is HyperdriveTest {
    using FixedPointMath for uint256;

    // TODO: Accrue interest before the test starts as this results in weirder
    // scenarios.
    function test_lp_withdrawal_long_immediate_close(
        uint128 basePaid,
        int64 preTradingApr
    ) external {
        uint256 apr = 0.02e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // TODO: We run into subtraction underflows when the pre trading APR is
        // negative because the spot price goes above 1. We should investigate
        // this further.
        //
        // Accrue interest before the trading period.
        vm.assume(preTradingApr >= 0e18 && preTradingApr <= 1e18);
        advanceTime(POSITION_DURATION, preTradingApr);

        // Bob opens a large long.
        vm.assume(
            basePaid >= 0.001e18 &&
                basePaid <= HyperdriveUtils.calculateMaxOpenLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Alice removes all of her LP shares.
        uint256 preRemovalSharePrice = HyperdriveUtils
            .getPoolInfo(hyperdrive)
            .sharePrice;
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        (contribution, ) = HyperdriveUtils.calculateCompoundInterest(
            contribution,
            preTradingApr,
            POSITION_DURATION
        );
        // TODO: This bound is too high. Investigate this further. Improving
        // this will have benefits on the remove liquidity unit tests.
        assertApproxEqAbs(
            baseProceeds,
            contribution - (longAmount - basePaid),
            1e9
        );
        assertApproxEqAbs(
            withdrawalShares,
            // TODO: The share price should be the same before and after. The
            // recent why it isn't is because the current share price
            // formulation is imprecise and results in very large withdrawals
            // getting a better share price than they should.
            (longAmount - basePaid).divDown(preRemovalSharePrice),
            10
        );

        // Bob closes his long. He will pay quite a bit of slippage on account
        // of the LP's removed liquidity.
        uint256 longProceeds = closeLong(bob, maturityTime, longAmount);
        assertGt(basePaid - longProceeds, withdrawalShares.mulDivDown(3, 4));

        // Alice redeems her withdrawal shares. She receives the unlocked margin
        // as well as quite a bit of "interest" that was collected from Bob's
        // slippage.
        uint256 sharePrice = HyperdriveUtils.getPoolInfo(hyperdrive).sharePrice;
        uint256 withdrawalProceeds = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertApproxEqAbs(
            withdrawalProceeds,
            // TODO: This bound is still too high.
            withdrawalShares.mulDown(sharePrice) + (basePaid - longProceeds),
            1e10
        );

        // TODO: This bound is unacceptably high. Investigate this when the
        // other bounds have been tightened.
        //
        // Ensure that the ending base balance of Hyperdrive is zero.
        assertApproxEqAbs(baseToken.balanceOf(address(hyperdrive)), 0, 1e11);
    }

    // TODO: Accrue interest before the test starts as this results in weirder
    // scenarios.
    //
    // TODO: Accrue interest after the test ends as this results in weirder
    // scenarios.
    //
    // TODO: We should also test that the withdrawal shares receive interest
    // if the long isn't closed immediately.
    function test_lp_withdrawal_long_redemption(
        uint128 basePaid,
        int64 variableApr
    ) external {
        uint256 apr = 0.02e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Bob opens a max long.
        vm.assume(
            basePaid >= 0.001e18 &&
                basePaid <= HyperdriveUtils.calculateMaxOpenLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Alice removes all of her LP shares.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        assertApproxEqAbs(
            baseProceeds,
            contribution - (longAmount - basePaid),
            1
        );
        assertEq(withdrawalShares, longAmount - basePaid);

        // Positive interest accrues over the term. We create a checkpoint for
        // the first checkpoint after opening the long to ensure that the
        // withdrawal shares will be accounted for properly.
        vm.assume(variableApr >= 0 && variableApr <= 2e18);
        advanceTime(CHECKPOINT_DURATION, variableApr);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));
        advanceTime(POSITION_DURATION - CHECKPOINT_DURATION, variableApr);

        // Bob closes his long. He should receive the full bond amount since he
        // is closing at maturity.
        uint256 longProceeds = closeLong(bob, maturityTime, longAmount);
        assertApproxEqAbs(longProceeds, longAmount, 10);

        // Alice redeems her withdrawal shares. She receives the interest
        // collected on the capital underlying the long for all but the first
        // checkpoint. This will leave dust which is the interest from the first
        // checkpoint compounded over the whole term.
        uint256 estimatedDust;
        int256 estimatedProceeds;
        {
            // TODO: We can solve this dust problem by storing a weighted
            // average of the starting share price for longs.
            (, int256 dustInterest) = HyperdriveUtils.calculateCompoundInterest(
                longAmount,
                variableApr,
                CHECKPOINT_DURATION
            );
            (estimatedDust, ) = HyperdriveUtils.calculateCompoundInterest(
                uint256(dustInterest),
                variableApr,
                POSITION_DURATION - CHECKPOINT_DURATION
            );
            (, estimatedProceeds) = HyperdriveUtils.calculateCompoundInterest(
                longAmount,
                variableApr,
                POSITION_DURATION - CHECKPOINT_DURATION
            );
        }
        uint256 withdrawalProceeds = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertApproxEqAbs(withdrawalProceeds, uint256(estimatedProceeds), 1e9);

        // Ensure that the ending base balance of Hyperdrive is zero.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            estimatedDust,
            1e9
        );
        assertApproxEqAbs(
            hyperdrive.totalSupply(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
            ),
            0,
            1
        );
    }
}
