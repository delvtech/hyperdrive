// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

// FIXME
import { console2 as console } from "forge-std/console2.sol";

import { stdError } from "forge-std/StdError.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

// FIXME:
//
// [ ] We need the following tests if they don't exist yet:
//     - [ ] Two LPs remove all of their liquidity and a long position matures.
//     - [ ] Two LPs remove all of their liquidity and a short position matures.
//     - [ ] All of the liquidity is removed and a long and short mature.
//     - [ ] One LP joins, and a long is opened. A new LP adds and removes
//           liquidity. Then the long is closed. The original LP should get
//           back their contribution.
//     - [ ] Tests with fees that ensure that any instantaneous trading will be
//           favorable for LPs that join the pool.
contract LpWithdrawalTest is HyperdriveTest {
    using FixedPointMath for int256;
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // TODO: We should use the default once we implement the feature that
        // pays out excess idle.
        //
        // Deploy Hyperdrive with a small minimum share reserves so that it is
        // negligible relative to our error tolerances.
        IHyperdrive.PoolConfig memory config = testConfig(0.05e18);
        config.minimumShareReserves = 1e6;
        deploy(deployer, config);
    }

    // This test is designed to ensure that a single LP receives all of the
    // trading profits earned when a new long position is closed immediately
    // after the LP withdraws. A bound is placed on these profits to ensure that
    // the removal of liquidity correctly increases the slippage that the long
    // must pay at the time of closing.
    function test_lp_withdrawal_long_immediate_close(
        uint256 basePaid,
        int256 preTradingVariableRate
    ) external {
        uint256 apr = 0.05e18;
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
        preTradingVariableRate = preTradingVariableRate.normalizeToRange(
            0e18,
            1e18
        );
        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a large long.
        basePaid = basePaid.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Alice removes all of her LP shares. She should recover her initial
        // contribution minus the amount of her capital that underlies Bob's
        // long position.
        uint256 estimatedLpProceeds = calculateBaseLpProceeds(lpShares);
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        (contribution, ) = HyperdriveUtils.calculateCompoundInterest(
            contribution,
            preTradingVariableRate,
            POSITION_DURATION
        );
        assertApproxEqAbs(baseProceeds, estimatedLpProceeds, 10);

        // Bob closes his long. He will pay quite a bit of slippage on account
        // of the LP's removed liquidity.
        uint256 longProceeds = closeLong(bob, maturityTime, longAmount);
        assertGt(basePaid - longProceeds, uint256(basePaid).mulDown(0.02e18));

        // Alice redeems her withdrawal shares. She gets back the capital that
        // was underlying to Bob's long position plus the profits that Bob paid in
        // slippage.
        (uint256 withdrawalProceeds, ) = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertApproxEqAbs(
            withdrawalProceeds,
            (longAmount - basePaid) + (basePaid - longProceeds),
            1e9 // TODO: Investigate this bound.
        );

        // Ensure the only remaining base is the base from the minimum share
        // reserves and the LP's present value.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().sharePrice
            ) + hyperdrive.presentValue(),
            10
        );
        // FIXME: Why isn't this zero? Shouldn't the present value be zero after
        // the long is closed?

        // TODO: This test should be fixed in the IDLE fix PR that alex will do
        // assertApproxEqAbs(
        //     hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID),
        //     0,
        //     1e9 // TODO: Investigate this bound.
        // );
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
        uint256 apr = 0.05e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);
        contribution -= 2 * hyperdrive.getPoolConfig().minimumShareReserves;

        // Bob opens a max long.
        basePaid = basePaid.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Alice removes all of her LP shares. She should recover her initial
        // contribution minus the amount of her capital that underlies Bob's
        // long position.
        uint256 estimatedLpProceeds = calculateBaseLpProceeds(lpShares);
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        {
            assertEq(baseProceeds, estimatedLpProceeds);
        }

        // Positive interest accrues over the term. We create a checkpoint for
        // the first checkpoint after opening the long to ensure that the
        // withdrawal shares will be accounted for properly.
        variableRate = variableRate.normalizeToRange(0, 2e18);
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
        {
            (uint256 withdrawalProceeds, ) = redeemWithdrawalShares(
                alice,
                withdrawalShares
            );
            assertApproxEqAbs(
                withdrawalProceeds,
                uint256(estimatedProceeds),
                1e10
            ); // TODO: Investigate this bound.
        }

        // Ensure the only remaining base is the base from the minimum share
        // reserves and the LP's present value.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().sharePrice
            ) + hyperdrive.presentValue(),
            1e10
        ); // TODO: Investigate this bound.
    }

    function test_lp_withdrawal_short_immediate_close(
        uint256 shortAmount,
        int256 preTradingVariableRate
    ) external {
        uint256 apr = 0.05e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // TODO: We run into subtraction underflows when the pre trading APR is
        // negative because the spot price goes above 1. We should investigate
        // this further.
        //
        // Accrue interest before the trading period.
        preTradingVariableRate = preTradingVariableRate.normalizeToRange(
            0,
            1e18
        );
        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a large short.
        vm.assume(
            shortAmount >= 0.001e18 &&
                shortAmount <= HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        shortAmount = shortAmount.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
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
        vm.expectRevert(stdError.arithmeticError);
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
        uint256 apr = 0.05e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);
        contribution -= 2 * hyperdrive.getPoolConfig().minimumShareReserves;

        // Bob opens a large short.
        shortAmount = shortAmount.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Alice removes all of her LP shares. She should recover her initial
        // contribution minus the amount of her capital that underlies Bob's
        // short position.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        assertApproxEqAbs(
            baseProceeds,
            contribution - (shortAmount - basePaid),
            1e6
        );

        // Positive interest accrues over the term.
        variableRate = variableRate.normalizeToRange(0, 2e18);
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
        (uint256 withdrawalProceeds, ) = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        // TODO: See if this bound can be lowered
        assertApproxEqAbs(withdrawalProceeds, shortAmount, 1e9); // TODO: Investigate this bound.

        // Ensure that the ending base balance of Hyperdrive is zero.
        assertApproxEqAbs(baseToken.balanceOf(address(hyperdrive)), 0, 1e9); // TODO: Investigate this bound.
        assertApproxEqAbs(
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID),
            0,
            1e9
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

    // FIXME: We should use the lpSharePrice more ubiquitously.
    //
    // This test ensures that two LPs (Alice and Celine) will receive a fair
    // share of the withdrawal pool's profits. After Alice initializes the pool,
    // Bob opens a long, and then Alice removes all of her liquidity. Celine
    // then adds liquidity, which improves Bob's ability to trade out of his
    // position. Bob then opens a short and Celine removes all of her liquidity.
    // We want to verify that Alice and Celine collectively receive all of the
    // the trading profits and that Celine is responsible for paying for the
    // increased slippage.
    function test_lp_withdrawal_long_and_short_maturity(
        uint256 longBasePaid,
        uint256 shortAmount,
        int256 variableRate
    ) external {

        // Set up the test parameters.
        TestLpWithdrawalParams memory testParams = TestLpWithdrawalParams({
            fixedRate: 0.05e18,
            variableRate: 0,
            contribution: 500_000_000e18,
            longAmount: 0,
            longBasePaid: 0,
            longMaturityTime: 0,
            shortAmount: 0,
            shortBasePaid: 0,
            shortMaturityTime: 0
        });

        // Initialize the pool.
        console.log("test: 1");
        uint256 aliceLpShares = initialize(
            alice,
            uint256(testParams.fixedRate),
            testParams.contribution
        );
        testParams.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;
        console.log("test: 2");

        // Bob opens a long.
        longBasePaid = longBasePaid.normalizeToRange(
            0.01e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        console.log("test: 3");

        testParams.longBasePaid = longBasePaid;
        {
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                bob,
                testParams.longBasePaid
            );
            testParams.longMaturityTime = longMaturityTime;
            testParams.longAmount = longAmount;
        }
        console.log("test: 4");

        // Alice removes all of her LP shares. She should recover her initial
        // contribution minus the amount of her capital that underlies Bob's
        // long position.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        uint256 aliceBaseProceeds;
        uint256 aliceWithdrawalShares;
        {
            uint256 estimatedLpBaseProceeds = calculateBaseLpProceeds(
                aliceLpShares
            );
            (aliceBaseProceeds, aliceWithdrawalShares) = removeLiquidity(
                alice,
                aliceLpShares
            );
            assertGe(
                aliceBaseProceeds +
                    aliceWithdrawalShares.mulDown(hyperdrive.lpSharePrice()),
                testParams.contribution
            );
            assertApproxEqAbs(aliceBaseProceeds, estimatedLpBaseProceeds, 1e9);
            assertApproxEqAbs(hyperdrive.lpSharePrice(), lpSharePrice, 1e6);
            lpSharePrice = hyperdrive.lpSharePrice();
        }
        console.log("test: 5");

        // Celine adds liquidity. When Celine adds liquidity, some of Alice's
        // withdrawal shares will be bought back at the current present value.
        // Since these are marked to market and removing liquidity increases
        // the present value, the lp share price should increase or stay the
        // same after this operation.
        uint256 celineLpShares = addLiquidity(celine, testParams.contribution);
        uint256 celineSlippagePayment = testParams.contribution -
            celineLpShares.mulDown(lpSharePrice);
        assertGe(hyperdrive.lpSharePrice() + 1e6, lpSharePrice);
        lpSharePrice = hyperdrive.lpSharePrice();
        console.log("test: 6");

        // Bob opens a short.
        shortAmount = shortAmount.normalizeToRange(
            0.01e18,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        testParams.shortAmount = shortAmount;
        {
            (uint256 shortMaturityTime, uint256 shortBasePaid) = openShort(
                bob,
                testParams.shortAmount
            );
            testParams.shortMaturityTime = shortMaturityTime;
            testParams.shortBasePaid = shortBasePaid;
        }
        console.log("test: 7");

        // Celine removes all of her LP shares. She should recover her initial
        // contribution minus the amount of capital that underlies the short
        // and the long.
        uint256 celineBaseProceeds;
        uint256 celineWithdrawalShares;
        {
            (celineBaseProceeds, celineWithdrawalShares) = removeLiquidity(
                celine,
                celineLpShares
            );
        }
        console.log("test: 8");

        // Time passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2e18);
        testParams.variableRate = variableRate;
        advanceTime(POSITION_DURATION, testParams.variableRate);
        console.log("test: 9");

        // Bob closes his long.
        closeLong(bob, testParams.longMaturityTime, testParams.longAmount);
        console.log("test: 10");

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
            assertApproxEqAbs(
                shortProceeds,
                uint256(expectedShortProceeds),
                1e9 // TODO: This bound is too large.
            );
        }
        console.log("test: 11");

        // Redeem the withdrawal shares. Alice and Celine should split the
        // withdrawal pool proportionally to their withdrawal shares.
        uint256 aliceRedeemProceeds;
        {
            uint256 sharesRedeemed;
            (aliceRedeemProceeds, sharesRedeemed) = redeemWithdrawalShares(
                alice,
                aliceWithdrawalShares
            );
            aliceWithdrawalShares -= sharesRedeemed;
        }
        uint256 celineRedeemProceeds;
        {
            uint256 sharesRedeemed;
            (celineRedeemProceeds, sharesRedeemed) = redeemWithdrawalShares(
                celine,
                celineWithdrawalShares
            );
            celineWithdrawalShares -= sharesRedeemed;
        }
        console.log("test: 12");

        // Ensure that Alice and Celine got back their initial contributions
        // minus any fixed interest that accrued to the underlying positions.
        // Alice or Celine may end up paying a larger fixed rate, but Celine
        // will be on the hook for her slippage payment.
        int256 fixedInterest = int256(testParams.shortBasePaid) -
            int256(testParams.longAmount - testParams.longBasePaid);
        assertGe(
            aliceBaseProceeds +
                aliceRedeemProceeds +
                aliceWithdrawalShares.mulDown(hyperdrive.lpSharePrice()),
            uint256(int256(testParams.contribution) + fixedInterest.min(0))
        );
        console.log("test: 13");
        assertGe(
            celineBaseProceeds +
                celineRedeemProceeds +
                celineWithdrawalShares.mulDown(hyperdrive.lpSharePrice()),
            uint256(
                int256(testParams.contribution - celineSlippagePayment) +
                    fixedInterest.min(0)
            )
        );
        console.log("test: 14");

        // Ensure that the ending base balance of Hyperdrive is zero.
        // TODO: See if this bound can be lowered
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().sharePrice
            ) + hyperdrive.presentValue(),
            1e9
        );
        console.log("test: 15");

        // Ensure that the ending supply of withdrawal shares is close to zero.
        // fails
        // TODO: This test should be fixed in the IDLE fix PR that alex will do
        // assertApproxEqAbs(
        //     hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID),
        //     0,
        //     1e9
        // );
    }

    // This test WILL FAIL with invalid share reserves on closeLong. You can make it pass in 3 ways:
    // 1. Make longBasePaid larger
    // 2. Make shortAmount larger
    // 3. Change the pool's initial fixed rate to something like 5%. This will
    // give the pool a smaller timestretch.
    // These 3 "solutions" create a large enough input s.t. the pow function
    // used in YieldSpace noise doesn't cause issues
    function test_lp_withdrawal_long_short_redemption_edge_case() external {
        uint256 longBasePaid = 14191; // 0.001000000000014191
        uint256 shortAmount = 19735436564515; // 0.001019735436564515
        int256 variableRate = 39997134772697; // 0.000039997134772697
        _test_lp_withdrawal_long_short_redemption(
            longBasePaid,
            shortAmount,
            variableRate
        );
    }

    function test_lp_withdrawal_long_short_redemption(
        uint256 longBasePaid,
        uint256 shortAmount,
        int256 variableRate
    ) external {
        _test_lp_withdrawal_long_short_redemption(
            longBasePaid,
            shortAmount,
            variableRate
        );
    }

    // FIXME: Add more lpSharePrice checks.
    //
    // FIXME: Update the description.
    //
    // This test ensures that two LPs (Alice and Celine) will receive a fair
    // share of the withdrawal pool's profits if Alice has entirely long
    // longExposure, Celine has entirely short exposure, Alice redeems immediately
    // after the long is closed, and Celine redeems after the short is redeemed.
    function _test_lp_withdrawal_long_short_redemption(
        uint256 longBasePaid,
        uint256 shortAmount,
        int256 variableRate
    ) internal {
        // Set up the test parameters.
        TestLpWithdrawalParams memory testParams = TestLpWithdrawalParams({
            fixedRate: 0.05e18,
            variableRate: 0,
            contribution: 500_000_000e18,
            longAmount: 0,
            longBasePaid: 0,
            longMaturityTime: 0,
            shortAmount: 0,
            shortBasePaid: 0,
            shortMaturityTime: 0
        });

        // Initialize the pool.
        uint256 aliceLpShares = initialize(
            alice,
            uint256(testParams.fixedRate),
            testParams.contribution
        );
        testParams.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Bob opens a long.
        longBasePaid = longBasePaid.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        testParams.longBasePaid = longBasePaid;
        {
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                bob,
                testParams.longBasePaid
            );
            testParams.longMaturityTime = longMaturityTime;
            testParams.longAmount = longAmount;
        }

        // Alice removes her liquidity.
        uint256 aliceWithdrawalShares = 0;
        uint256 aliceBaseProceeds = 0;
        {
            uint256 estimatedBaseLpProceeds = calculateBaseLpProceeds(
                aliceLpShares
            );
            (aliceBaseProceeds, aliceWithdrawalShares) = removeLiquidity(
                alice,
                aliceLpShares
            );
            assertApproxEqAbs(
                aliceBaseProceeds,
                estimatedBaseLpProceeds,
                1e9 // TODO: Try to shrink this bound.
            );
        }

        // Celine adds liquidity.
        uint256 celineLpShares = addLiquidity(celine, testParams.contribution);
        uint256 celineSlippagePayment = testParams.contribution -
            celineLpShares.mulDown(hyperdrive.lpSharePrice());

        uint256 aliceRedeemProceeds;
        {
            // Redeem Alice's withdrawal shares. Alice should receive the margin
            // released from Bob's long as well as a payment for the additional
            // slippage incurred by Celine adding liquidity. She should be left with
            // no withdrawal shares.
            (aliceRedeemProceeds, ) = redeemWithdrawalShares(
                alice,
                aliceWithdrawalShares
            );
            aliceWithdrawalShares = hyperdrive.balanceOf(
                AssetId._WITHDRAWAL_SHARE_ASSET_ID,
                alice
            );
            // TODO: This test should be fixed in the IDLE fix PR that alex will do
            // assertApproxEqAbs(
            //     aliceRedeemProceeds,
            //     testParams.longAmount + celineSlippagePayment,
            //     1e11
            // );
            //assertApproxEqAbs(aliceWithdrawalShares, 0, 1e11);
        }

        // Bob opens a short.
        shortAmount = shortAmount.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        testParams.shortAmount = shortAmount;
        {
            (uint256 shortMaturityTime, uint256 shortBasePaid) = openShort(
                bob,
                testParams.shortAmount
            );
            testParams.shortMaturityTime = shortMaturityTime;
            testParams.shortBasePaid = shortBasePaid;
        }
        // Celine removes her liquidity.
        uint256 celineBaseProceeds = 0;
        uint256 celineWithdrawalShares = 0;
        {
            uint256 estimatedBaseLpProceeds = calculateBaseLpProceeds(
                celineLpShares
            );
            (celineBaseProceeds, celineWithdrawalShares) = removeLiquidity(
                celine,
                celineLpShares
            );

            assertApproxEqAbs(
                celineBaseProceeds,
                estimatedBaseLpProceeds,
                1e11
            );
        }
        // Time passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2e18);
        testParams.variableRate = variableRate;
        advanceTime(POSITION_DURATION, testParams.variableRate);

        // Bob closes his long.
        closeLong(bob, testParams.longMaturityTime, testParams.longAmount);

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

        // Redeem the withdrawal shares. Alice and Celine will split the face
        // value of the short in the proportion of their withdrawal shares.
        (uint256 aliceRemainingRedeemProceeds, ) = redeemWithdrawalShares(
            alice,
            aliceWithdrawalShares
        );
        (uint256 celineRedeemProceeds, ) = redeemWithdrawalShares(
            celine,
            celineWithdrawalShares
        );

        // Ensure that Alice and Celine got back their initial contributions.
        aliceRedeemProceeds += aliceRemainingRedeemProceeds;
        assertGt(
            aliceBaseProceeds + aliceRedeemProceeds,
            testParams.contribution
        );

        // TODO: I think this test should be fixed in the IDLE fix PR that alex will do
        // assertGt(
        //     celineBaseProceeds + celineRedeemProceeds,
        //     testParams.contribution - celineSlippagePayment
        // );

        // Ensure that the ending base balance of Hyperdrive is zero.

        // TODO: This test should be fixed in the IDLE fix PR that alex will do.
        // Normally this works, but when variable interest is high (e.g. 200%) the leftover shares
        // earn enough variable interest to make this fail.
        //assertApproxEqAbs(baseToken.balanceOf(address(hyperdrive)), 0, 1e9); // TODO: This bound is too large

        // TODO: This test should be fixed in the IDLE fix PR that alex will do
        // assertApproxEqAbs(
        //     hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID),
        //     0,
        //     1e9
        // );
    }

    function test_lp_withdrawal_three_lps(
        uint256 longBasePaid,
        uint256 shortAmount
    ) external {
        _test_lp_withdrawal_three_lps(longBasePaid, shortAmount);
    }

    function test_lp_withdrawal_three_lps_edge_cases() external {
        // This is an edge case that occurs when the output of the
        // YieldSpaceMath is approximately equal to zero. Previously, we would
        // have an arithmetic underflow since we round up the value being
        // subtracted.
        _test_lp_withdrawal_three_lps(8181, 19983965771856);
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
    function _test_lp_withdrawal_three_lps(
        uint256 longBasePaid,
        uint256 shortAmount
    ) internal {
        // Set up the test parameters.
        TestLpWithdrawalParams memory testParams = TestLpWithdrawalParams({
            fixedRate: 0.05e18,
            variableRate: 0,
            contribution: 500_000_000e18,
            longAmount: 0,
            longBasePaid: 0,
            longMaturityTime: 0,
            shortAmount: 0,
            shortBasePaid: 0,
            shortMaturityTime: 0
        });

        // Initialize the pool.
        uint256 aliceLpShares = initialize(
            alice,
            uint256(testParams.fixedRate),
            testParams.contribution
        );
        testParams.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Bob adds liquidity.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        uint256 bobLpShares = addLiquidity(bob, testParams.contribution);
        assertEq(hyperdrive.lpSharePrice(), lpSharePrice);
        lpSharePrice = hyperdrive.lpSharePrice();

        // Bob opens a long.
        longBasePaid = longBasePaid.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        testParams.longBasePaid = longBasePaid;
        {
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                bob,
                testParams.longBasePaid
            );
            testParams.longMaturityTime = longMaturityTime;
            testParams.longAmount = longAmount;
        }
        assertApproxEqAbs(hyperdrive.lpSharePrice(), lpSharePrice, 100);
        lpSharePrice = hyperdrive.lpSharePrice();

        // Bob opens a short.
        shortAmount = shortAmount.normalizeToRange(
            0.001e18,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        testParams.shortAmount = shortAmount;
        {
            (uint256 shortMaturityTime, uint256 shortBasePaid) = openShort(
                bob,
                testParams.shortAmount
            );
            testParams.shortMaturityTime = shortMaturityTime;
            testParams.shortBasePaid = shortBasePaid;
        }
        assertApproxEqAbs(hyperdrive.lpSharePrice(), lpSharePrice, 100);
        lpSharePrice = hyperdrive.lpSharePrice();
        uint256 estimatedLpProceeds = calculateBaseLpProceeds(aliceLpShares);

        // Alice removes her liquidity.
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);
        assertEq(aliceBaseProceeds, estimatedLpProceeds);
        assertApproxEqAbs(hyperdrive.lpSharePrice(), lpSharePrice, 10);
        lpSharePrice = hyperdrive.lpSharePrice();

        // Celine adds liquidity.
        uint256 celineLpShares = addLiquidity(celine, testParams.contribution);
        // FIXME: This is an untenable large bound. Why is the current value
        // even larger than the contribution?
        assertApproxEqAbs(hyperdrive.lpSharePrice(), lpSharePrice, 1e16);
        lpSharePrice = hyperdrive.lpSharePrice();

        // Bob closes his long and his short.
        {
            closeLong(bob, testParams.longMaturityTime, testParams.longAmount);
            closeShort(
                bob,
                testParams.shortMaturityTime,
                testParams.shortAmount
            );
        }

        // Redeem Alice's withdrawal shares. Alice should get at least the
        // margin released from Bob's long.
        (uint256 aliceRedeemProceeds, ) = redeemWithdrawalShares(
            alice,
            aliceWithdrawalShares
        );

        // Alice withdraws at least the original contribution.
        assertGe(
            aliceRedeemProceeds + aliceBaseProceeds,
            testParams.contribution
        );

        // Bob and Celine remove their liquidity. Bob should receive more base
        // proceeds than Celine since Celine's add liquidity resulted in an
        // increase in slippage for the outstanding positions.
        (
            uint256 bobBaseProceeds,
            uint256 bobWithdrawalShares
        ) = removeLiquidity(bob, bobLpShares);
        (
            uint256 celineBaseProceeds,
            uint256 celineWithdrawalShares
        ) = removeLiquidity(celine, celineLpShares);
        assertGt(bobBaseProceeds, celineBaseProceeds);
        assertGt(bobBaseProceeds, testParams.contribution);
        assertApproxEqAbs(bobWithdrawalShares, 0, 1);
        assertApproxEqAbs(celineWithdrawalShares, 0, 1);

        assertApproxEqAbs(
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID) -
                hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw,
            0,
            1e9 // TODO: Why is this not equal to zero?
        );
    }
}
