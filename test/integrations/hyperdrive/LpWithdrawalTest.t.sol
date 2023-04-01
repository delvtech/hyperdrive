// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

// TODO: Some scenarios that we need to test.
//
// - [ ] A mixture of long and short trades.
// - [ ] LPs with different long and short weightings.
contract LpWithdrawalTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function test_lp_withdrawal_long_immediate_close(
        uint256 basePaid,
        int256 preTradingVariableRate
    ) external {
        uint256 apr = 0.02e18;
        uint256 contribution = 500_000_000e18;
        uint256 baseBalanceBefore = baseToken.balanceOf(address(hyperdrive));
        uint256 lpShares = initialize(alice, apr, contribution);

        // Normalize the fuzzing input.
        basePaid = basePaid.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        // TODO: We run into subtraction underflows when the pre trading APR is
        // negative because the spot price goes above 1. We should investigate
        // this further. The specific error is caused by a spot price that is 1
        // or 2 wei greater than 1e18:
        //
        // FAIL. Reason: FixedPointMath_SubOverflow() Counterexample: calldata=0xeb03bc3c00000000000000000000000000000000000000000056210439729b8099325834fffffffffffffffffffffffffffffffffffffffffffffffff923591560ca3e4c, args=[104123536507311086290229300, -494453585727570356]]
        preTradingVariableRate = preTradingVariableRate.normalizeToRange(
            0,
            1e18
        );

        // Accrue interest before the trading period.
        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a large long.
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Alice removes all of her LP shares.
        uint256 baseProceeds;
        uint256 withdrawalShares;
        {
            uint256 preRemovalSharePrice = hyperdrive.getPoolInfo().sharePrice;
            (baseProceeds, withdrawalShares) = removeLiquidity(alice, lpShares);
            (contribution, ) = HyperdriveUtils.calculateCompoundInterest(
                contribution,
                preTradingVariableRate,
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
                // reason why it isn't is because the current share price
                // formulation is imprecise and results in very large withdrawals
                // getting a better share price than they should.
                (longAmount - basePaid).divDown(preRemovalSharePrice),
                10
            );
        }

        // Bob closes his long. He will pay quite a bit of slippage on account
        // of the LP's removed liquidity.
        uint256 longProceeds = closeLong(bob, maturityTime, longAmount);
        assertGt(basePaid - longProceeds, withdrawalShares.mulDivDown(3, 4));

        // Alice redeems her withdrawal shares. She receives the unlocked margin
        // as well as quite a bit of "interest" that was collected from Bob's
        // slippage.
        {
            uint256 sharePrice = hyperdrive.getPoolInfo().sharePrice;
            uint256 withdrawalProceeds = redeemWithdrawalShares(
                alice,
                withdrawalShares
            );
            assertApproxEqAbs(
                withdrawalProceeds,
                // TODO: This bound is still too high.
                withdrawalShares.mulDown(sharePrice) +
                    (basePaid - longProceeds),
                1e9
            );
        }

        // TODO: This bound is unacceptably high. Investigate this when the
        // other bounds have been tightened.
        //
        // Ensure that the ending base balance of Hyperdrive is zero.
        (uint256 baseBalanceBeforePlusInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(
                baseBalanceBefore,
                preTradingVariableRate,
                POSITION_DURATION
            );
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalanceBeforePlusInterest,
            1e9
        );
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
        uint256 basePaid,
        int256 variableRate
    ) external {
        uint256 apr = 0.02e18;
        uint256 contribution = 500_000_000e18;
        uint256 baseBalanceBefore = baseToken.balanceOf(address(hyperdrive));
        uint256 lpShares = initialize(alice, apr, contribution);

        // Normalize the fuzzing input.
        basePaid = basePaid.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        variableRate = variableRate.normalizeToRange(0, 2e18);

        // Bob opens a max long.
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
        advanceTime(CHECKPOINT_DURATION, variableRate);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));
        advanceTime(POSITION_DURATION - CHECKPOINT_DURATION, variableRate);

        // Bob closes his long. He should receive the full bond amount since he
        // is closing at maturity.
        uint256 longProceeds = closeLong(bob, maturityTime, longAmount);
        assertApproxEqAbs(longProceeds, longAmount, 10);

        // Alice redeems her withdrawal shares. She receives the interest
        // collected on the capital underlying the long for all but the first
        // checkpoint. This will leave dust which is the interest from the first
        // checkpoint compounded over the whole term.
        (, int256 estimatedProceeds) = HyperdriveUtils
            .calculateCompoundInterest(
                longAmount,
                variableRate,
                POSITION_DURATION
            );
        uint256 withdrawalProceeds = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertApproxEqAbs(withdrawalProceeds, uint256(estimatedProceeds), 1e10);

        // Ensure that the ending base balance of Hyperdrive is zero.
        (uint256 baseBalanceBeforePlusInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(
                baseBalanceBefore,
                variableRate,
                POSITION_DURATION
            );
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalanceBeforePlusInterest,
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

    function test_lp_withdrawal_short_immediate_close(
        uint256 shortAmount,
        int256 preTradingVariableRate
    ) external {
        uint256 apr = 0.02e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Normalize the fuzzing input.
        shortAmount = shortAmount.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        // TODO: We run into subtraction underflows when the pre trading APR is
        // negative because the spot price goes above 1. We should investigate
        // this further.
        preTradingVariableRate = preTradingVariableRate.normalizeToRange(
            0,
            1e18
        );

        // Accrue interest before the trading period.
        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a large short.
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Alice removes all of her LP shares.
        uint256 preRemovalSharePrice = hyperdrive.getPoolInfo().sharePrice;
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        (contribution, ) = HyperdriveUtils.calculateCompoundInterest(
            contribution,
            preTradingVariableRate,
            POSITION_DURATION
        );
        // TODO: This bound is too high. Investigate this further. Improving
        // this will have benefits on the remove liquidity unit tests.
        assertApproxEqAbs(
            baseProceeds,
            contribution - (shortAmount - basePaid),
            1e9
        );
        // TODO: This bound is too high.
        assertApproxEqAbs(
            withdrawalShares,
            // TODO: The share price should be the same before and after. The
            // recent why it isn't is because the current share price
            // formulation is imprecise and results in very large withdrawals
            // getting a better share price than they should.
            (shortAmount - basePaid).divDown(preRemovalSharePrice),
            1e9
        );

        // TODO: We need to think more about this. This may or may not be
        // acceptable.
        //
        // Bob attempts to close his short. This will fail since there isn't any
        // liquidity in the pool after Alice removed her liquidity.
        vm.expectRevert(Errors.FixedPointMath_SubOverflow.selector);
        vm.stopPrank();
        vm.startPrank(bob);
        hyperdrive.closeShort(maturityTime, shortAmount, 0, bob, true);
    }

    // TODO: Accrue interest before the test starts as this results in weirder
    // scenarios.
    //
    // TODO: Accrue interest after the test ends as this results in weirder
    // scenarios.
    //
    // TODO: We should also test that the withdrawal shares receive interest
    // if the long isn't closed immediately.
    function test_lp_withdrawal_short_redemption(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        uint256 apr = 0.02e18;
        uint256 contribution = 500_000_000e18;
        uint256 baseBalanceBefore = baseToken.balanceOf(address(hyperdrive));
        uint256 lpShares = initialize(alice, apr, contribution);

        // Normalize the fuzzing input.
        shortAmount = shortAmount.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        variableRate = variableRate.normalizeToRange(0, 2e18);

        // Bob opens a large short.
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Alice removes all of her LP shares.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        assertEq(baseProceeds, contribution - (shortAmount - basePaid));
        assertEq(withdrawalShares, shortAmount - basePaid);

        // Interest accrues over the term.
        advanceTime(POSITION_DURATION, variableRate);

        // Bob closes his short. His proceeds should be the variable interest
        // that accrued on the short amount over the period.
        uint256 shortProceeds = closeShort(bob, maturityTime, shortAmount);
        (, int256 expectedInterest) = HyperdriveUtils.calculateCompoundInterest(
            shortAmount,
            variableRate,
            POSITION_DURATION
        );
        // TODO: See if this bound can be lowered
        assertApproxEqAbs(shortProceeds, uint256(expectedInterest), 1e9);

        // Alice redeems her withdrawal shares. She receives the margin that she
        // put up as well as the fixed interest paid by the short.
        uint256 withdrawalProceeds = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        // TODO: See if this bound can be lowered
        assertApproxEqAbs(withdrawalProceeds, shortAmount, 1e9);

        // Ensure that the ending base balance of Hyperdrive is zero.
        (uint256 baseBalanceBeforePlusInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(
                baseBalanceBefore,
                variableRate,
                POSITION_DURATION
            );
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalanceBeforePlusInterest,
            1e9
        ); // TODO: See if this bound can be lowered
        assertApproxEqAbs(
            hyperdrive.totalSupply(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
            ),
            0,
            1
        );
    }

    struct TestLpWithdrawalLongShortImmediateParams {
        int256 fixedRate;
        int256 variableRate;
        uint256 contribution;
        uint256 longAmount;
        uint256 longBasePaid;
        uint256 longMaturityTime;
        uint256 shortAmount;
        uint256 shortBasePaid;
        uint256 shortMaturityTime;
    }

    // TODO: Add more tests like this where the redemptions happen at different
    //       times.
    function test_lp_withdrawal_long_and_short_immediate(
        uint256 longBasePaid,
        uint256 shortAmount,
        uint256 variableRate
    ) external {
        // Normalize the fuzzing input.
        longBasePaid = longBasePaid.normalizeToRange(0.001e18, 20_000_000e18); // TODO: use larger amounts.
        shortAmount = shortAmount.normalizeToRange(0.001e18, 20_000_000e18); // TODO: use larger amounts.
        variableRate = variableRate.normalizeToRange(0, 2e18);

        // Set up the test parameters.
        TestLpWithdrawalLongShortImmediateParams
            memory testParams = TestLpWithdrawalLongShortImmediateParams({
                fixedRate: 0.02e18,
                variableRate: int256(uint256(variableRate)),
                contribution: 500_000_000e18,
                longAmount: 0,
                longBasePaid: 10_000_000e18,
                longMaturityTime: 0,
                shortAmount: 10_000_000e18,
                shortBasePaid: 0,
                shortMaturityTime: 0
            });

        // Get the base balance before initializing the pool.
        uint256 baseBalanceBefore = baseToken.balanceOf(address(hyperdrive));

        // Initialize the pool.
        uint256 aliceLpShares = initialize(
            alice,
            uint256(testParams.fixedRate),
            testParams.contribution
        );

        // Bob opens a long.
        {
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                bob,
                testParams.longBasePaid
            );
            testParams.longMaturityTime = longMaturityTime;
            testParams.longAmount = longAmount;
        }

        // Alice removes her liquidity.
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(
            aliceBaseProceeds,
            testParams.contribution -
                (testParams.longAmount - testParams.longBasePaid),
            1e9
        );
        assertApproxEqAbs(
            aliceWithdrawalShares,
            testParams.longAmount - testParams.longBasePaid,
            10
        );

        // Celine adds liquidity.
        uint256 celineLpShares = addLiquidity(celine, 500_000_000e18);

        // Bob opens a short.
        {
            (uint256 shortMaturityTime, uint256 shortBasePaid) = openShort(
                bob,
                testParams.shortAmount
            );
            testParams.shortMaturityTime = shortMaturityTime;
            testParams.shortBasePaid = shortBasePaid;
        }

        // Celine removes her liquidity.
        uint256 celineWithdrawalShares;
        {
            uint256 celineBaseProceeds;
            (celineBaseProceeds, celineWithdrawalShares) = removeLiquidity(
                celine,
                celineLpShares
            );
            assertApproxEqAbs(
                celineBaseProceeds,
                testParams.contribution -
                    (testParams.shortAmount - testParams.shortBasePaid),
                1e9
            );
            // TODO: This bound is too high.
            assertApproxEqAbs(
                celineWithdrawalShares,
                testParams.shortAmount - testParams.shortBasePaid,
                1e9
            );
        }

        // Bob closes his long.
        {
            uint256 longProceeds = closeLong(
                bob,
                testParams.longMaturityTime,
                testParams.longAmount
            );
            assertGt(longProceeds, testParams.longAmount.mulDown(0.9e18)); // TODO: Can this be tightened?
        }

        // Bob attempts to close, but the operation fails with an arithmetic
        // error. This will succeed after waiting for the rest of the term to
        // elapse.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.FixedPointMath_SubOverflow.selector);
        hyperdrive.closeShort(
            testParams.shortMaturityTime,
            testParams.shortAmount,
            0,
            bob,
            true
        );

        // TODO: Fuzz the APR.
        advanceTime(POSITION_DURATION, testParams.variableRate);

        // Bob closes the short at redemption.
        {
            uint256 shortProceeds = closeShort(
                bob,
                testParams.shortMaturityTime,
                testParams.shortAmount
            );
            (, int256 expectedShortProceeds) = HyperdriveUtils
                .calculateCompoundInterest(
                    testParams.shortAmount,
                    testParams.variableRate,
                    POSITION_DURATION
                );
            // TODO: Try to shrink this bound.
            assertApproxEqAbs(
                shortProceeds,
                uint256(expectedShortProceeds),
                1e9
            );
        }

        // Redeem the withdrawal shares. Alice and Celine should each receive
        // the minimum of the fixed and variable rate interest.
        uint256 aliceRedeemProceeds = redeemWithdrawalShares(
            alice,
            aliceWithdrawalShares
        );
        uint256 celineRedeemProceeds = redeemWithdrawalShares(
            celine,
            celineWithdrawalShares
        );
        {
            (, int256 fixedInterest) = HyperdriveUtils.calculateInterest(
                testParams.longAmount - testParams.longBasePaid,
                testParams.fixedRate,
                POSITION_DURATION
            );
            (, int256 variableInterest) = HyperdriveUtils
                .calculateCompoundInterest(
                    testParams.longAmount - testParams.longBasePaid,
                    testParams.variableRate,
                    POSITION_DURATION
                );
            int256 expectedInterest = fixedInterest >= variableInterest
                ? variableInterest
                : fixedInterest;
            assertGt(
                aliceRedeemProceeds,
                uint256(
                    int256(testParams.longAmount - testParams.longBasePaid) +
                        expectedInterest
                )
            );
        }
        {
            (, int256 fixedInterest) = HyperdriveUtils.calculateInterest(
                testParams.shortAmount - testParams.shortBasePaid,
                testParams.fixedRate,
                POSITION_DURATION
            );
            (, int256 variableInterest) = HyperdriveUtils
                .calculateCompoundInterest(
                    testParams.shortAmount - testParams.shortBasePaid,
                    testParams.variableRate,
                    POSITION_DURATION
                );
            int256 expectedInterest = fixedInterest >= variableInterest
                ? variableInterest
                : fixedInterest;
            assertGt(
                celineRedeemProceeds,
                uint256(
                    int256(testParams.shortAmount - testParams.shortBasePaid) +
                        expectedInterest
                )
            );
        }

        // Ensure that the ending base balance of Hyperdrive is zero.
        (uint256 baseBalanceBeforePlusInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(
                baseBalanceBefore,
                testParams.variableRate,
                POSITION_DURATION
            );
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalanceBeforePlusInterest,
            1e8
        ); // TODO: See if this bound can be lowered
        assertApproxEqAbs(
            hyperdrive.totalSupply(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
            ),
            0,
            1
        );
    }
}
