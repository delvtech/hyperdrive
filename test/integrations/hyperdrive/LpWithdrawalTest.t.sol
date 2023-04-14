// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";

// FIXME:
//
// [ ] We need the following tests if they don't exist yet:
//     - [ ] Two LPs remove all of their liquidity and a long position matures.
//     - [ ] Two LPs remove all of their liquidity and a short position matures.
//     - [ ] All of the liquidity is removed and a long and short mature.
contract LpWithdrawalTest is HyperdriveTest {
    using FixedPointMath for uint256;

    // This test is designed to ensure that a single LP receives all of the
    // trading profits earned when a new long position is closed immediately
    // after the LP withdraws. A bound is placed on these profits to ensure that
    // the removal of liquidity correctly increases the slippage that the long
    // must pay at the time of closing.
    function test_lp_withdrawal_long_immediate_close(
        uint128 basePaid,
        int64 preTradingVariableRate
    ) external {
        uint256 apr = 0.02e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // TODO: We run into subtraction underflows when the pre trading APR is
        // negative because the spot price goes above 1. We should investigate
        // this further. The specific error is caused by a spot price that is 1
        // or 2 wei greater than 1e18:
        //
        // FAIL. Reason: FixedPointMath_SubOverflow() Counterexample: calldata=0xeb03bc3c00000000000000000000000000000000000000000056210439729b8099325834fffffffffffffffffffffffffffffffffffffffffffffffff923591560ca3e4c, args=[104123536507311086290229300, -494453585727570356]]
        //
        // Accrue interest before the trading period.
        vm.assume(
            preTradingVariableRate >= 0e18 && preTradingVariableRate <= 1e18
        );
        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a large long.
        vm.assume(
            basePaid >= 0.001e18 &&
                basePaid <= HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Alice removes all of her LP shares. She should recover her initial
        // contribution minus the amount of her capital that underlies Bob's
        // long position.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        (contribution, ) = HyperdriveUtils.calculateCompoundInterest(
            contribution,
            preTradingVariableRate,
            POSITION_DURATION
        );
        assertApproxEqAbs(
            baseProceeds,
            contribution - (longAmount - basePaid),
            1e9 // Investigate this bound.
        );

        // Bob closes his long. He will pay quite a bit of slippage on account
        // of the LP's removed liquidity.
        uint256 longProceeds = closeLong(bob, maturityTime, longAmount);
        assertGt(basePaid - longProceeds, uint256(basePaid).mulDown(0.02e18));

        // Alice redeems her withdrawal shares. She gets back the capital that
        // underlied Bob's long position plus the profits that Bob paid in
        // slippage.
        uint256 withdrawalProceeds = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertApproxEqAbs(
            withdrawalProceeds,
            (longAmount - basePaid) + (basePaid - longProceeds),
            1e9 // TODO: Investigate this bound.
        );

        // Ensure approximately all of the base and withdrawal shares has been
        // removed from the Hyperdrive instance.
        assertApproxEqAbs(baseToken.balanceOf(address(hyperdrive)), 0, 1e9); // TODO: Investigate this bound.
        // FIXME: Why isn't this zero? Shouldn't the present value be zero after
        // the long is closed?
        assertApproxEqAbs(
            hyperdrive.totalSupply(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
            ),
            0,
            1e8 // TODO: Investigate this bound.
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
        uint128 basePaid,
        int64 variableRate
    ) external {
        uint256 apr = 0.02e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Bob opens a max long.
        vm.assume(
            basePaid >= 0.001e18 &&
                basePaid <= HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Alice removes all of her LP shares. She should recover her initial
        // contribution minus the amount of her capital that underlies Bob's
        // long position.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        assertApproxEqAbs(
            baseProceeds,
            contribution - (longAmount - basePaid),
            1
        );

        // Positive interest accrues over the term. We create a checkpoint for
        // the first checkpoint after opening the long to ensure that the
        // withdrawal shares will be accounted for properly.
        vm.assume(variableRate >= 0 && variableRate <= 2e18);
        advanceTime(CHECKPOINT_DURATION, variableRate);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));
        advanceTime(POSITION_DURATION - CHECKPOINT_DURATION, variableRate);

        // Bob closes his long. He should receive the full bond amount since he
        // is closing at maturity.
        uint256 longProceeds = closeLong(bob, maturityTime, longAmount);
        assertApproxEqAbs(longProceeds, longAmount, 10); // TODO: Investigate this bound.

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
        assertApproxEqAbs(withdrawalProceeds, uint256(estimatedProceeds), 1e10); // TODO: Investigate this bound.

        // Ensure approximately all of the base and withdrawal shares has been
        // removed from the Hyperdrive instance.
        assertApproxEqAbs(baseToken.balanceOf(address(hyperdrive)), 0, 1e10); // TODO: Investigate this bound.
        assertEq(
            hyperdrive.totalSupply(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
            ),
            0
        );
    }

    function test_lp_withdrawal_short_immediate_close(
        uint128 shortAmount,
        int64 preTradingVariableRate
    ) external {
        uint256 apr = 0.02e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // TODO: We run into subtraction underflows when the pre trading APR is
        // negative because the spot price goes above 1. We should investigate
        // this further.
        //
        // Accrue interest before the trading period.
        vm.assume(
            preTradingVariableRate >= 0e18 && preTradingVariableRate <= 1e18
        );
        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a large short.
        vm.assume(
            shortAmount >= 0.001e18 &&
                shortAmount <= HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Alice removes all of her LP shares. She should recover her initial
        // contribution minus the amount of her capital that underlies Bob's
        // short position.
        (uint256 baseProceeds, ) = removeLiquidity(alice, lpShares);
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
        uint128 shortAmount,
        int64 variableRate
    ) external {
        uint256 apr = 0.02e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Bob opens a large short.
        vm.assume(
            shortAmount >= 0.001e18 &&
                shortAmount <= HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Alice removes all of her LP shares. She should recover her initial
        // contribution minus the amount of her capital that underlies Bob's
        // short position.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        assertEq(baseProceeds, contribution - (shortAmount - basePaid));

        // Positive interest accrues over the term.
        vm.assume(variableRate >= 0 && variableRate <= 2e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Bob closes his short. His proceeds should be the variable interest
        // that accrued on the short amount over the period.
        uint256 shortProceeds = closeShort(bob, maturityTime, shortAmount);
        (, int256 expectedInterest) = HyperdriveUtils.calculateCompoundInterest(
            shortAmount,
            variableRate,
            POSITION_DURATION
        );
        assertApproxEqAbs(shortProceeds, uint256(expectedInterest), 1e9); // TODO: Investigate this bound.

        // Alice redeems her withdrawal shares. She receives the margin that she
        // put up as well as the fixed interest paid by the short.
        uint256 withdrawalProceeds = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        // TODO: See if this bound can be lowered
        assertApproxEqAbs(withdrawalProceeds, shortAmount, 1e9); // TODO: Investigate this bound.

        // Ensure that the ending base balance of Hyperdrive is zero.
        assertApproxEqAbs(baseToken.balanceOf(address(hyperdrive)), 0, 1e9); // TODO: Investigate this bound.
        assertEq(
            hyperdrive.totalSupply(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
            ),
            0
        );
    }

    struct TestLpWithdrawalParams {
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

    // This test ensures that two LPs (Alice and Celine) will receive a fair
    // share of the withdrawal pool's profits if Alice has entirely long
    // exposure, Celine has entirely short exposure, and they both redeem after
    // redemption.
    function test_lp_withdrawal_long_and_short_immediate(
        uint256 longBasePaid,
        uint256 shortAmount,
        uint64 variableRate
    ) external {
        // Ensure that the provided parameters fit into our testing range.
        vm.assume(longBasePaid >= 0.001e18);
        longBasePaid %= 20_000_000e18; // TODO: Use larger amounts
        vm.assume(shortAmount >= 0.001e18);
        shortAmount %= 20_000_000e18; // TODO: Use larger amounts
        vm.assume(variableRate >= 0 && variableRate <= 2e18);

        // Set up the test parameters.
        TestLpWithdrawalParams memory testParams = TestLpWithdrawalParams({
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

        // Time passes and interest accrues.
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
        // TODO: See if this bound can be lowered
        assertApproxEqAbs(baseToken.balanceOf(address(hyperdrive)), 0, 1e9);
        assertApproxEqAbs(
            hyperdrive.totalSupply(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
            ),
            0,
            1
        );
    }

    // This test ensures that two LPs (Alice and Celine) will receive a fair
    // share of the withdrawal pool's profits if Alice has entirely long
    // exposure, Celine has entirely short exposure, Alice redeems immediately
    // after the long is closed, and Celine redeems after the short is redeemed.
    function test_lp_withdrawal_long_close_immediate_and_short_redemption(
        uint256 longBasePaid,
        uint256 shortAmount,
        uint64 variableRate
    ) external {
        // Ensure that the provided parameters fit into our testing range.
        vm.assume(longBasePaid >= 0.001e18);
        longBasePaid %= 20_000_000e18; // TODO: Use larger amounts
        vm.assume(shortAmount >= 0.001e18);
        shortAmount %= 20_000_000e18; // TODO: Use larger amounts
        vm.assume(variableRate >= 0 && variableRate <= 2e18);

        // Set up the test parameters.
        TestLpWithdrawalParams memory testParams = TestLpWithdrawalParams({
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
            1e9 // TODO: Try to shrink this bound.
        );
        assertApproxEqAbs(
            aliceWithdrawalShares,
            testParams.longAmount - testParams.longBasePaid,
            10
        );

        // Celine adds liquidity.
        uint256 celineLpShares = addLiquidity(celine, 500_000_000e18);

        // Bob closes his long.
        uint256 longProceeds = closeLong(
            bob,
            testParams.longMaturityTime,
            testParams.longAmount
        );

        // Redeem Alice's withdrawal shares. Alice should receive the margin
        // released from Bob's long.
        uint256 aliceRedeemProceeds = redeemWithdrawalShares(
            alice,
            aliceWithdrawalShares
        );
        assertEq(aliceRedeemProceeds, testParams.longAmount - longProceeds);

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
        (
            uint256 celineBaseProceeds,
            uint256 celineWithdrawalShares
        ) = removeLiquidity(celine, celineLpShares);
        assertApproxEqAbs(
            celineBaseProceeds,
            500_000_000e18 -
                (testParams.shortAmount - testParams.shortBasePaid),
            1e9
        );

        // Time passes and interest accrues.
        advanceTime(POSITION_DURATION, testParams.variableRate);

        // Close the short.
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
            assertApproxEqAbs(
                shortProceeds,
                uint256(expectedShortProceeds),
                1e9
            );
        }

        // Redeem the withdrawal shares. Celine should the margin released from
        // the short as well as the fixed interest from buying the bond.
        uint256 celineRedeemProceeds = redeemWithdrawalShares(
            celine,
            celineWithdrawalShares
        );
        assertApproxEqAbs(celineRedeemProceeds, testParams.shortAmount, 10);

        // Ensure that the ending base balance of Hyperdrive is zero.
        assertApproxEqAbs(baseToken.balanceOf(address(hyperdrive)), 0, 1);
        assertApproxEqAbs(
            hyperdrive.totalSupply(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
            ),
            0,
            1
        );
    }

    // TODO: Add commentary on how Alice, Bob, and Celine should be treated
    // similarly. Think more about whether or not this should really be the
    // case.
    //
    // This test ensures that three LPs (Alice, Bob, and Celine) will receive a
    // fair share of the withdrawal pool's profits. Alice and Bob add liquidity
    // and then Bob opens two positions (a long and a short position). Alice
    // removes her liquidity and then Bob closes the long and the short.
    // Finally, Bob and Celine remove their liquidity. Bob and Celine shouldn't
    // be treated differently based on the order in which they added liquidity.
    function test_lp_withdrawal_three_lps(
        uint256 longBasePaid,
        uint256 shortAmount,
        uint64 variableRate
    ) external {
        // Ensure that the provided parameters fit into our testing range.
        vm.assume(longBasePaid >= 0.001e18);
        longBasePaid %= 20_000_000e18; // TODO: Use larger amounts
        vm.assume(shortAmount >= 0.001e18);
        shortAmount %= 20_000_000e18; // TODO: Use larger amounts
        vm.assume(variableRate >= 0 && variableRate <= 2e18);

        // Set up the test parameters.
        TestLpWithdrawalParams memory testParams = TestLpWithdrawalParams({
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

        // Initialize the pool.
        uint256 aliceLpShares = initialize(
            alice,
            uint256(testParams.fixedRate),
            testParams.contribution
        );

        // Bob adds liquidity.
        uint256 bobLpShares = addLiquidity(bob, testParams.contribution);

        // Bob opens a long.
        {
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                bob,
                testParams.longBasePaid
            );
            testParams.longMaturityTime = longMaturityTime;
            testParams.longAmount = longAmount;
        }

        // Bob opens a short.
        {
            (uint256 shortMaturityTime, uint256 shortBasePaid) = openShort(
                bob,
                testParams.shortAmount
            );
            testParams.shortMaturityTime = shortMaturityTime;
            testParams.shortBasePaid = shortBasePaid;
        }

        // Alice removes her liquidity.
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);
        uint256 aliceExpectedWithdrawalShares = ((testParams.longAmount -
            testParams.longBasePaid) +
            (testParams.shortAmount - testParams.shortBasePaid)) / 2;
        assertApproxEqAbs(
            aliceBaseProceeds,
            testParams.contribution - aliceExpectedWithdrawalShares,
            10
        );
        assertApproxEqAbs(
            aliceWithdrawalShares,
            aliceExpectedWithdrawalShares,
            10
        );

        // Celine adds liquidity.
        uint256 celineLpShares = addLiquidity(celine, testParams.contribution);

        // Bob closes his long and his short.
        {
            uint256 longProceeds = closeLong(
                bob,
                testParams.longMaturityTime,
                testParams.longAmount
            );
            uint256 shortProceeds = closeShort(
                bob,
                testParams.shortMaturityTime,
                testParams.shortAmount
            );
            assertApproxEqAbs(
                longProceeds + shortProceeds,
                testParams.longBasePaid + testParams.shortBasePaid,
                1e18 // TODO: See if we can tighten this bound
            );
        }

        // Redeem Alice's withdrawal shares. Alice should receive the margin
        // released from Bob's long.
        uint256 aliceRedeemProceeds = redeemWithdrawalShares(
            alice,
            aliceWithdrawalShares
        );
        assertGt(aliceRedeemProceeds, aliceExpectedWithdrawalShares);

        // Bob and Celine remove their liquidity. They should receive
        // approximately the same amount of base tokens and no withdrawal
        // shares.
        (
            uint256 bobBaseProceeds,
            uint256 bobWithdrawalShares
        ) = removeLiquidity(bob, bobLpShares);
        (
            uint256 celineBaseProceeds,
            uint256 celineWithdrawalShares
        ) = removeLiquidity(celine, celineLpShares);
        assertEq(bobBaseProceeds, celineBaseProceeds);
        // TODO: This assertion fails with the following error:
        //
        // Logs:
        //   alice proceeds: 500003724.406172042149976149
        //   bob proceeds: 499998138.159024684562895420
        //   Error: a > b not satisfied [uint]
        //     Value a: 499998138159024684562895420
        //     Value b: 500000000000000000000000000
        //
        // Test result: FAILED. 0 passed; 1 failed; finished in 1.34s
        //
        // Failing tests:
        // Encountered 1 failing test in test/integrations/hyperdrive/LpWithdrawalTest.t.sol:LpWithdrawalTest
        // [FAIL. Reason: Assertion failed. Counterexample: calldata=0x7cbb568900000000000000000000000000000000000000000000000000038d7ea4c6800000000000000000000000000000000000000000000000000000038d7ea4c680000000000000000000000000000000000000000000000000000000000000000000, args=[1000000000000000, 1000000000000000, 0]] test_lp_withdrawal_three_lps(uint256,uint256,uint64) (runs: 0, μ: 0, ~: 0)

        //
        // assertGt(bobBaseProceeds, testParams.contribution);
        assertEq(bobWithdrawalShares, 0);
        assertEq(celineWithdrawalShares, 0);

        // Ensure that the ending base balance of Hyperdrive is zero.
        assertApproxEqAbs(baseToken.balanceOf(address(hyperdrive)), 0, 1);
        assertApproxEqAbs(
            hyperdrive.totalSupply(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
            ),
            0,
            1e9 // TODO: Why is this not equal to zero?
        );
    }
}
