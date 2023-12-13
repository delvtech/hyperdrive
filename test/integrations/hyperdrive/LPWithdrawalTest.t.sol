// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdError } from "forge-std/StdError.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract LPWithdrawalTest is HyperdriveTest {
    using FixedPointMath for int256;
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Deploy Hyperdrive with a small minimum share reserves so that it is
        // negligible relative to our error tolerances.
        IHyperdrive.PoolConfig memory config = testConfig(0.05e18);
        deploy(deployer, config);
    }

    // FIXME: This test case allows us to hit the edge case where some of the
    //        net longs can't be closed. Flesh this out and make sure that our
    //        invariants hold.
    // function test_example() external {
    //     // Alice initializes the pool
    //     uint256 apr = 0.05e18;
    //     uint256 contribution = 500_000_000e18;
    //     uint256 lpShares = initialize(alice, apr, contribution);
    //
    //     // Bob opens a max short.
    //     openShort(
    //         bob,
    //         hyperdrive.calculateMaxShort()
    //     );
    //
    //     // The term advances and no interest accrues.
    //     advanceTime(POSITION_DURATION, 0);
    //     hyperdrive.checkpoint(hyperdrive.latestCheckpoint());
    //
    //     // Bob opens a max long.
    //     (, uint256 longAmount) = openLong(
    //         bob,
    //         hyperdrive.calculateMaxLong()
    //     );
    //     console.log("long amount = %s", longAmount.toString(18));
    //
    //     // Alice removes all of her LP shares.
    //     removeLiquidity(alice, lpShares / 5);
    //
    //     // Bob adds liquidity.
    //     addLiquidity(bob, 10e18);
    // }

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

        // Accrue interest before the trading period.
        preTradingVariableRate = preTradingVariableRate.normalizeToRange(
            0e18,
            1e18
        );
        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a large long.
        basePaid = basePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT * 2,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // FIXME: Make sure that Alice receives all of the pool's idle capital.
        //
        // Alice removes all of her LP shares. The LP share price should be
        // approximately equal before and after the transaction.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Bob closes his long. He will pay quite a bit of slippage on account
        // of the LP's removed liquidity. The LP share price should be
        // approximately equal before and after the transaction.
        lpSharePrice = hyperdrive.lpSharePrice();
        closeLong(bob, maturityTime, longAmount);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e9)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Alice redeems her withdrawal shares. She gets back the capital that
        // was underlying to Bob's long position plus the profits that Bob paid in
        // slippage.
        lpSharePrice = hyperdrive.lpSharePrice();
        (uint256 withdrawalProceeds, ) = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e9)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // We expect Alice's withdrawal proceeds are greater than or equal
        // (with a fudge factor) to the amount predicted by the LP share
        // price.
        assertGe(
            withdrawalProceeds + 1e9,
            withdrawalShares.mulDown(lpSharePrice)
        );

        // Ensure that the ending base balance of Hyperdrive only consists of
        // the minimum share reserves and address zero's LP shares.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().sharePrice + hyperdrive.lpSharePrice()
            ),
            1e9
        );

        // TODO(jalextowle and jrhea): This is such a deep edge case, that it
        // doesn't really make sense to me to special case it (by paying out
        // all of the withdrawal pool). If the pool's present value goes to 0,
        // it's dead IMO.
        //
        // Ensure that the ending supply of withdrawal shares is close to zero.
        if (hyperdrive.presentValue() > 0) {
            assertApproxEqAbs(
                hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID),
                0,
                1
            );
        }
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
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // FIXME: It would be good to make sure that she receives all of the
        // pool's idle capital.
        //
        // Alice removes all of her LP shares. The LP share price should be
        // approximately equal before and after the transaction, and the value
        // of her overall portfolio should be greater than or equal to her
        // original portfolio value.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);
        assertGe(
            baseProceeds + withdrawalShares.mulDown(hyperdrive.lpSharePrice()),
            contribution
        );

        // Positive interest accrues over the term. We create a checkpoint for
        // the first checkpoint after opening the long to ensure that the
        // withdrawal shares will be accounted for properly.
        variableRate = variableRate.normalizeToRange(0, 2e18);
        advanceTime(CHECKPOINT_DURATION, variableRate);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));
        advanceTime(POSITION_DURATION - CHECKPOINT_DURATION, variableRate);

        // Bob closes his long. He should receive the full bond amount since he
        // is closing at maturity. The LP share price should be approximately
        // equal before and after the transaction.
        lpSharePrice = hyperdrive.lpSharePrice();
        uint256 longProceeds = closeLong(bob, maturityTime, longAmount);
        assertApproxEqAbs(longProceeds, longAmount, 10); // TODO: Investigate this bound.
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14).max(1e9)
        );

        // Alice redeems her withdrawal shares.
        {
            // Ensure that the LP share price is approximately equal before and
            // after the transaction.
            lpSharePrice = hyperdrive.lpSharePrice();
            (uint256 withdrawalProceeds, ) = redeemWithdrawalShares(
                alice,
                withdrawalShares
            );
            assertApproxEqAbs(
                lpSharePrice,
                hyperdrive.lpSharePrice(),
                lpSharePrice.mulDown(1e14)
            );
            assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

            // We expect Alice's withdrawal proceeds are greater than or equal
            // (with a fudge factor) to the amount predicted by the LP share
            // price.
            assertGe(
                withdrawalProceeds + 1e9,
                withdrawalShares.mulDown(lpSharePrice)
            );
        }

        // Ensure that the ending base balance of Hyperdrive only consists of
        // the minimum share reserves and address zero's LP shares.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().sharePrice + hyperdrive.lpSharePrice()
            ),
            1e9
        );

        // TODO(jalextowle and jrhea): This is such a deep edge case, that it
        // doesn't really make sense to me to special case it (by paying out
        // all of the withdrawal pool). If the pool's present value goes to 0,
        // it's dead IMO.
        //
        // Ensure that the ending supply of withdrawal shares is close to zero.
        if (hyperdrive.presentValue() > 0) {
            assertApproxEqAbs(
                hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID),
                0,
                1
            );
        }
    }

    function test_lp_withdrawal_short_immediate_close(
        uint256 shortAmount,
        int256 preTradingVariableRate
    ) external {
        uint256 apr = 0.05e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Accrue interest before the trading period.
        preTradingVariableRate = preTradingVariableRate.normalizeToRange(
            0,
            1e18
        );
        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a large short.
        shortAmount = shortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // FIXME: Ensure that either (1) all of the idle was paid out, (2) all
        // of the withdrawal shares were paid out, or (3) the max share reserves
        // delta was fully exhausted.
        //
        // Alice removes all of her LP shares. The LP share price should be
        // conserved.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        removeLiquidity(alice, lpShares);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Ensure that Bob can close his short. The system must always be able
        // to close the net short position to ensure that we don't enter a
        // regime where the present value can start increasing when liquidity
        // is removed.
        closeShort(bob, maturityTime, shortAmount);
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
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // FIXME: Ensure that either (1) all of the idle was paid out, (2) all
        // of the withdrawal shares were paid out, or (3) the max share reserves
        // delta was fully exhausted.
        //
        // Alice removes all of her LP shares. She should recover her initial
        // contribution minus the amount of her capital that underlies Bob's
        // short position.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Positive interest accrues over the term.
        variableRate = variableRate.normalizeToRange(0, 2e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Bob closes his short. His proceeds should be the variable interest
        // that accrued on the short amount over the period.
        lpSharePrice = hyperdrive.lpSharePrice();
        uint256 shortProceeds = closeShort(bob, maturityTime, shortAmount);
        (, int256 expectedInterest) = HyperdriveUtils.calculateCompoundInterest(
            shortAmount,
            variableRate,
            POSITION_DURATION
        );
        assertApproxEqAbs(shortProceeds, uint256(expectedInterest), 1e9); // TODO: Investigate this bound.
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Alice redeems her withdrawal shares.
        lpSharePrice = hyperdrive.lpSharePrice();
        (uint256 withdrawalProceeds, ) = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Ensure that Alice's proceeds are greater than or equal to her initial
        // contribution.
        assertGe(baseProceeds + withdrawalProceeds, contribution);

        // Ensure that the ending base balance of Hyperdrive only consists of
        // the minimum share reserves and address zero's LP shares.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().sharePrice + hyperdrive.lpSharePrice()
            ),
            1e9
        );

        // TODO(jalextowle and jrhea): This is such a deep edge case, that it
        // doesn't really make sense to me to special case it (by paying out
        // all of the withdrawal pool). If the pool's present value goes to 0,
        // it's dead IMO.
        //
        // Ensure that the ending supply of withdrawal shares is close to zero.
        if (hyperdrive.presentValue() > 0) {
            assertApproxEqAbs(
                hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID),
                0,
                1
            );
        }
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

    function test_lp_withdrawal_long_and_short_maturity(
        uint256 longBasePaid,
        uint256 shortAmount,
        int256 variableRate
    ) external {
        _test_lp_withdrawal_long_and_short_maturity(
            longBasePaid,
            shortAmount,
            variableRate
        );
    }

    function test_lp_withdrawal_long_and_short_maturity_edge_cases() external {
        uint256 snapshotId = vm.snapshot();
        {
            uint256 longBasePaid = 4510; // 0.001000000000004510
            uint256 shortAmount = 49890332890205; // 0.001049890332890205
            int256 variableRate = 2381976568446569244243622252022378995313; // 0.633967799094373787
            _test_lp_withdrawal_long_and_short_maturity(
                longBasePaid,
                shortAmount,
                variableRate
            );
        }
        vm.revertTo(snapshotId);
        {
            uint256 longBasePaid = 952379451834619; // 0.001952379451834619
            uint256 shortAmount = 1049989096786962; // 0.002049989096786962
            int256 variableRate = 31603980; // 0.000000000031603980
            _test_lp_withdrawal_long_and_short_maturity(
                longBasePaid,
                shortAmount,
                variableRate
            );
        }
        // This edge case led to insolvency with the old netting implementation.
        // It results in the short receiving a higher fixed rate than the long,
        // which causes more idle to be removed than is safe.
        vm.revertTo(snapshotId);
        {
            uint256 longBasePaid = 340282366920938463427525853467631535298;
            uint256 shortAmount = 466484623342087836179459133;
            int256 variableRate = 10428;
            _test_lp_withdrawal_long_and_short_maturity(
                longBasePaid,
                shortAmount,
                variableRate
            );
        }
        // This edge case resulted in a negative present value.
        vm.revertTo(snapshotId);
        {
            uint256 longBasePaid = 489677686070469885716015664;
            uint256 shortAmount = 499999997999962236523722993;
            int256 variableRate = 9996;
            _test_lp_withdrawal_long_and_short_maturity(
                longBasePaid,
                shortAmount,
                variableRate
            );
        }
        // This edge csaes results in the LP share price approaching zero
        // because the variable rate is close to zero and the net position is
        // entirely long.
        vm.revertTo(snapshotId);
        {
            uint256 longBasePaid = 11709480438780642194;
            uint256 shortAmount = 0;
            int256 variableRate = 2;
            _test_lp_withdrawal_long_and_short_maturity(
                longBasePaid,
                shortAmount,
                variableRate
            );
        }
    }

    // This test ensures that two LPs (Alice and Celine) will receive a fair
    // share of the withdrawal pool's profits. After Alice initializes the pool,
    // Bob opens a long, and then Alice removes all of her liquidity. Celine
    // then adds liquidity, which improves Bob's ability to trade out of his
    // position. Bob then opens a short and Celine removes all of her liquidity.
    // We want to verify that Alice and Celine collectively receive all of the
    // the trading profits and that Celine is responsible for paying for the
    // increased slippage.
    function _test_lp_withdrawal_long_and_short_maturity(
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
        testParams.longBasePaid = longBasePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (testParams.longMaturityTime, testParams.longAmount) = openLong(
            bob,
            testParams.longBasePaid
        );

        // FIXME: Make sure that all of the idle capital was consumed.
        //
        // Alice removes all of her LP shares. Ensure that the LP share price is
        // approximately equal after removing liquidity and that it is greater
        // than or equal to the previous LP share price.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Ensure that Alice's present value is greater than or equal to her
        // contribution.
        assertGe(
            aliceBaseProceeds +
                aliceWithdrawalShares.mulDown(hyperdrive.lpSharePrice()),
            testParams.contribution
        );

        // Celine adds liquidity. When Celine adds liquidity, some of Alice's
        // withdrawal shares will be bought back at the current present value.
        // Since these are marked to market and removing liquidity increases
        // the present value, the lp share price should increase or stay the
        // same after this operation.
        lpSharePrice = hyperdrive.lpSharePrice();
        uint256 celineLpShares = addLiquidity(celine, testParams.contribution);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);
        uint256 celineSlippagePayment = testParams.contribution -
            celineLpShares.mulDown(lpSharePrice);

        // Bob opens a short.
        testParams.shortAmount = shortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        lpSharePrice = hyperdrive.lpSharePrice();
        (testParams.shortMaturityTime, testParams.shortBasePaid) = openShort(
            bob,
            testParams.shortAmount
        );
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Celine removes all of her LP shares. She should recover her initial
        // contribution minus the amount of capital that underlies the short
        // and the long. Ensure that the LP share price is approximately equal
        // after removing liquidity  and that it is greater than or equal to the
        // previous LP share price.
        lpSharePrice = hyperdrive.lpSharePrice();
        (
            uint256 celineBaseProceeds,
            uint256 celineWithdrawalShares
        ) = removeLiquidity(celine, celineLpShares);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Time passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2e18);
        testParams.variableRate = variableRate;
        advanceTime(POSITION_DURATION, testParams.variableRate);

        // Bob closes his long.
        lpSharePrice = hyperdrive.lpSharePrice();
        closeLong(bob, testParams.longMaturityTime, testParams.longAmount);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            // NOTE: In the deep edge-case where a long is opened and the
            // variable rate is zero, the LP share price can be very close
            // to zero. Since this case is so rare and unrealistic, we just
            // ignore it.
            lpSharePrice.mulDown(1e14).max(1e9)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Bob closes the short at redemption.
        {
            // Ensure that the LP share price is approximately equal after
            // closing the short and that it is greater than or equal to the
            // previous LP share price.
            lpSharePrice = hyperdrive.lpSharePrice();
            uint256 shortProceeds = closeShort(
                bob,
                testParams.shortMaturityTime,
                testParams.shortAmount
            );
            assertApproxEqAbs(
                lpSharePrice,
                hyperdrive.lpSharePrice(),
                lpSharePrice.mulDown(1e14)
            );
            assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

            // Ensure that the short proceeds are approximately equal to the
            // variable interest that accrued over the term.
            (, int256 expectedShortProceeds) = HyperdriveUtils
                .calculateCompoundInterest(
                    testParams.shortAmount,
                    testParams.variableRate,
                    POSITION_DURATION
                );
            assertApproxEqAbs(
                shortProceeds,
                uint256(expectedShortProceeds),
                1e10 // TODO: This bound is too large.
            );
        }

        // Redeem the withdrawal shares. Alice and Celine should split the
        // withdrawal pool proportionally to their withdrawal shares.
        uint256 aliceRedeemProceeds;
        {
            uint256 sharesRedeemed;
            lpSharePrice = hyperdrive.lpSharePrice();
            (aliceRedeemProceeds, sharesRedeemed) = redeemWithdrawalShares(
                alice,
                aliceWithdrawalShares
            );
            aliceWithdrawalShares -= sharesRedeemed;
            assertApproxEqAbs(
                lpSharePrice,
                hyperdrive.lpSharePrice(),
                lpSharePrice.mulDown(1e14)
            );
            assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);
        }
        uint256 celineRedeemProceeds;
        {
            uint256 sharesRedeemed;
            lpSharePrice = hyperdrive.lpSharePrice();
            (celineRedeemProceeds, sharesRedeemed) = redeemWithdrawalShares(
                celine,
                celineWithdrawalShares
            );
            celineWithdrawalShares -= sharesRedeemed;
            assertApproxEqAbs(
                lpSharePrice,
                hyperdrive.lpSharePrice(),
                lpSharePrice.mulDown(1e14)
            );
            assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);
        }

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
        assertGe(
            celineBaseProceeds +
                celineRedeemProceeds +
                celineWithdrawalShares.mulDown(hyperdrive.lpSharePrice()) +
                1e10,
            uint256(
                int256(testParams.contribution - celineSlippagePayment) +
                    fixedInterest.min(0)
            )
        );

        // Ensure that the ending base balance of Hyperdrive only consists of
        // the minimum share reserves and address zero's LP shares.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().sharePrice + hyperdrive.lpSharePrice()
            ),
            1e9
        );

        // TODO(jalextowle and jrhea): This is such a deep edge case, that it
        // doesn't really make sense to me to special case it (by paying out
        // all of the withdrawal pool). If the pool's present value goes to 0,
        // it's dead IMO.
        //
        // Ensure that the ending supply of withdrawal shares is close to zero.
        if (hyperdrive.presentValue() > 0) {
            assertApproxEqAbs(
                hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID),
                0,
                1
            );
        }
    }

    function test_lp_withdrawal_long_short_redemption_edge_case() external {
        uint256 snapshotId = vm.snapshot();
        {
            uint256 longBasePaid = 14191; // 0.001000000000014191
            uint256 shortAmount = 19735436564515; // 0.001019735436564515
            int256 variableRate = 39997134772697; // 0.000039997134772697
            _test_lp_withdrawal_long_short_redemption(
                longBasePaid,
                shortAmount,
                variableRate
            );
        }
        vm.revertTo(snapshotId);
        {
            uint256 longBasePaid = 4107; //0.001000000000004107
            uint256 shortAmount = 49890332890205; //0.001049890332890205
            int256 variableRate = 1051037269400789; //0.001051037269400789
            _test_lp_withdrawal_long_short_redemption(
                longBasePaid,
                shortAmount,
                variableRate
            );
        }
        vm.revertTo(snapshotId);
        {
            uint256 longBasePaid = 47622440666488;
            uint256 shortAmount = 99991360285271;
            int256 variableRate = 25629;
            _test_lp_withdrawal_long_short_redemption(
                longBasePaid,
                shortAmount,
                variableRate
            );
        }
        // This edge case caused the present value to become negative.
        vm.revertTo(snapshotId);
        {
            uint256 longBasePaid = 9359120568038014548496614986532107423060977700952779944229929110473;
            uint256 shortAmount = 6363481524035208645046457754761807956049413076188199707925459155397040;
            int256 variableRate = 0;
            _test_lp_withdrawal_long_short_redemption(
                longBasePaid,
                shortAmount,
                variableRate
            );
        }
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

    // FIXME: Take another pass through this test.
    //
    // FIXME: Throughout this test make sure that either all the idle was
    // distributed or all of the withdrawal shares were distributed.
    //
    // This test ensures that two LPs (Alice and Celine) will receive a fair
    // share of the withdrawal pool's profits if Alice has entirely long
    // exposure, Celine has entirely short exposure, Alice redeems immediately
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
        testParams.longBasePaid = longBasePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        (testParams.longMaturityTime, testParams.longAmount) = openLong(
            bob,
            testParams.longBasePaid
        );

        // Alice removes her liquidity.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // FIXME: Clean up this block
        uint256 celineLpShares;
        uint256 aliceRedeemProceeds;
        uint256 celineSlippagePayment;
        {
            // Celine adds liquidity.
            lpSharePrice = hyperdrive.lpSharePrice();
            celineLpShares = addLiquidity(celine, testParams.contribution);
            celineSlippagePayment =
                testParams.contribution -
                celineLpShares.mulDown(hyperdrive.lpSharePrice());
            assertApproxEqAbs(
                lpSharePrice,
                hyperdrive.lpSharePrice(),
                lpSharePrice.mulDown(1e14)
            );
            assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

            // Redeem Alice's withdrawal shares. Alice should receive the margin
            // released from Bob's long as well as a payment for the additional
            // slippage incurred by Celine adding liquidity. She should be left with
            // no withdrawal shares.
            lpSharePrice = hyperdrive.lpSharePrice();
            uint256 sharesRedeemed;
            (aliceRedeemProceeds, sharesRedeemed) = redeemWithdrawalShares(
                alice,
                aliceWithdrawalShares
            );
            aliceWithdrawalShares -= sharesRedeemed;
            assertApproxEqAbs(
                lpSharePrice,
                hyperdrive.lpSharePrice(),
                lpSharePrice.mulDown(1e14)
            );
            assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

            // Record the value of Alice's withdrawal shares after Celine adds
            // liquidity and Alice redeems some of her withdrawal shares.
            uint256 aliceWithdrawalSharesValueAfter = aliceWithdrawalShares
                .mulDown(hyperdrive.lpSharePrice()) + aliceRedeemProceeds;

            // Ensure that the user expects to make at least as much money as
            // they put in.
            assertGe(
                aliceBaseProceeds + aliceWithdrawalSharesValueAfter,
                testParams.contribution
            );
        }

        // Bob opens a short.
        testParams.shortAmount = shortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        lpSharePrice = hyperdrive.lpSharePrice();
        (testParams.shortMaturityTime, testParams.shortBasePaid) = openShort(
            bob,
            testParams.shortAmount
        );
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Celine removes her liquidity.
        lpSharePrice = hyperdrive.lpSharePrice();
        (
            uint256 celineBaseProceeds,
            uint256 celineWithdrawalShares
        ) = removeLiquidity(celine, celineLpShares);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Time passes and interest accrues.
        testParams.variableRate = variableRate.normalizeToRange(0, 2e18);
        advanceTime(POSITION_DURATION, testParams.variableRate);

        // Bob closes his long.
        lpSharePrice = hyperdrive.lpSharePrice();
        closeLong(bob, testParams.longMaturityTime, testParams.longAmount);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14).max(1e9)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Close the short.
        {
            lpSharePrice = hyperdrive.lpSharePrice();
            uint256 shortProceeds = closeShort(
                bob,
                testParams.shortMaturityTime,
                testParams.shortAmount
            );
            assertApproxEqAbs(
                lpSharePrice,
                hyperdrive.lpSharePrice(),
                lpSharePrice.mulDown(1e14).max(1e9)
            );
            assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);
            (, int256 expectedShortProceeds) = HyperdriveUtils
                .calculateCompoundInterest(
                    testParams.shortAmount,
                    testParams.variableRate,
                    POSITION_DURATION
                );
            assertApproxEqAbs(
                shortProceeds,
                uint256(expectedShortProceeds),
                1e10
            );
        }

        // FIXME: Check to see that Celine got the correct base proceeds.
        //
        // Redeem the withdrawal shares. Alice and Celine will split the face
        // value of the short in the proportion of their withdrawal shares.
        uint256 aliceRemainingRedeemProceeds;
        {
            uint256 sharesRedeemed;
            lpSharePrice = hyperdrive.lpSharePrice();
            (
                aliceRemainingRedeemProceeds,
                sharesRedeemed
            ) = redeemWithdrawalShares(alice, aliceWithdrawalShares);
            aliceWithdrawalShares -= sharesRedeemed;
            assertApproxEqAbs(
                lpSharePrice,
                hyperdrive.lpSharePrice(),
                lpSharePrice.mulDown(1e14)
            );
            assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);
        }
        // FIXME: Check to see that Celine got the correct base proceeds.
        uint256 celineRedeemProceeds;
        {
            uint256 sharesRedeemed;
            lpSharePrice = hyperdrive.lpSharePrice();
            (celineRedeemProceeds, sharesRedeemed) = redeemWithdrawalShares(
                celine,
                celineWithdrawalShares
            );
            assertApproxEqAbs(
                lpSharePrice,
                hyperdrive.lpSharePrice(),
                lpSharePrice.mulDown(1e14)
            );
            assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);
        }

        // FIXME: Use this check everywhere.
        //
        // Ensure that the ending base balance of Hyperdrive only consists of
        // the minimum share reserves and address zero's LP shares.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().sharePrice + hyperdrive.lpSharePrice()
            ),
            1e9
        );

        // TODO(jalextowle and jrhea): This is such a deep edge case, that it
        // doesn't really make sense to me to special case it (by paying out
        // all of the withdrawal pool). If the pool's present value goes to 0,
        // it's dead IMO.
        //
        // Ensure that the ending supply of withdrawal shares is close to zero.
        if (hyperdrive.presentValue() > 0) {
            assertApproxEqAbs(
                hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID),
                0,
                1
            );
        }
    }

    function test_single_lp_withdrawal_long_short_redemption_edge_case()
        external
    {
        uint256 longBasePaid = 11754624137;
        uint256 shortAmount = 49890332890205;
        _test_single_lp_withdrawal_long_short_redemption(
            longBasePaid,
            shortAmount
        );
    }

    function test_single_lp_withdrawal_long_short_redemption(
        uint256 longBasePaid,
        uint256 shortAmount
    ) external {
        _test_single_lp_withdrawal_long_short_redemption(
            longBasePaid,
            shortAmount
        );
    }

    // FIXME: Make sure all of the idle is paid out or one of the other
    // invariants was hit.
    //
    // This test is designed to find cases where the longs are insolvent after
    // the LP removes funds and the short is closed. This will only pass if the
    // long exposure is calculated to account for the cases where the shorts
    // deposit is larger than the long's fixed rate, but the short is shorting
    // less bonds than the long is longing.
    function _test_single_lp_withdrawal_long_short_redemption(
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

        shortAmount = shortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT * 2,
            hyperdrive.calculateMaxShort()
        );
        (uint256 shortWithInterest, ) = HyperdriveUtils.calculateInterest(
            shortAmount,
            testParams.fixedRate,
            POSITION_DURATION
        );
        uint256 longLowerBound = shortAmount.mulDown(
            shortAmount.divDown(shortWithInterest)
        );
        longBasePaid = longBasePaid.normalizeToRange(
            longLowerBound,
            shortAmount
        );
        longBasePaid = longBasePaid.min(hyperdrive.calculateMaxLong());

        // Bob opens a long.
        testParams.longBasePaid = longBasePaid;
        (testParams.longMaturityTime, testParams.longAmount) = openLong(
            bob,
            testParams.longBasePaid
        );

        // Bob opens a short.
        testParams.shortAmount = shortAmount;
        (testParams.shortMaturityTime, testParams.shortBasePaid) = openShort(
            bob,
            testParams.shortAmount
        );

        // Alice removes her liquidity.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Time passes and no interest accrues.
        advanceTime(POSITION_DURATION, 0);

        // Bob closes his long.
        lpSharePrice = hyperdrive.lpSharePrice();
        closeLong(bob, testParams.longMaturityTime, testParams.longAmount);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Close the short.
        {
            lpSharePrice = hyperdrive.lpSharePrice();
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
                1e10
            );
            assertApproxEqAbs(
                lpSharePrice,
                hyperdrive.lpSharePrice(),
                lpSharePrice.mulDown(1e14)
            );
            assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);
        }

        // Redeem the withdrawal shares. Alice and Celine will split the face
        // value of the short in the proportion of their withdrawal shares.
        uint256 aliceRemainingRedeemProceeds;
        {
            uint256 sharesRedeemed;
            lpSharePrice = hyperdrive.lpSharePrice();
            (
                aliceRemainingRedeemProceeds,
                sharesRedeemed
            ) = redeemWithdrawalShares(alice, aliceWithdrawalShares);
            aliceWithdrawalShares -= sharesRedeemed;
            assertApproxEqAbs(
                lpSharePrice,
                hyperdrive.lpSharePrice(),
                lpSharePrice.mulDown(1e14)
            );
            assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);
        }

        // Ensure that the ending base balance of Hyperdrive only consists of
        // the minimum share reserves and address zero's LP shares.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().sharePrice + hyperdrive.lpSharePrice()
            ),
            1e9
        );

        // TODO(jalextowle and jrhea): This is such a deep edge case, that it
        // doesn't really make sense to me to special case it (by paying out
        // all of the withdrawal pool). If the pool's present value goes to 0,
        // it's dead IMO.
        //
        // Ensure that the ending supply of withdrawal shares is close to zero.
        if (hyperdrive.presentValue() > 0) {
            assertApproxEqAbs(
                hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID),
                0,
                1
            );
        }
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
        uint256 snapshotId = vm.snapshot();
        {
            uint256 longBasePaid = 8181;
            uint256 shortAmount = 19983965771856;
            _test_lp_withdrawal_three_lps(longBasePaid, shortAmount);
        }
        // This is an old edge case that we unfortunately don't have a reason
        // for anymore.
        vm.revertTo(snapshotId);
        {
            uint256 longBasePaid = 112173584723002853004121113797378997258679744955268467156471905609758801845023;
            uint256 shortAmount = 549812613265172043897083640351978971711251998278;
            _test_lp_withdrawal_three_lps(longBasePaid, shortAmount);
        }
        // FIXME
        //
        // // This edge case resulted in the LP share price increasing more than
        // // 0.01% after distributing excess idle liquidity.
        // vm.revertTo(snapshotId);
        // {
        //     uint256 longBasePaid = 469991228879638584073946043;
        //     uint256 shortAmount = 2043170798149466600528688795244803555758742315187834115121;
        //     _test_lp_withdrawal_three_lps(longBasePaid, shortAmount);
        // }
        // FIXME
        //
        // // This edge case resulted in the LP share price decreasing after
        // // distributing excess idle liquidity.
        // vm.revertTo(snapshotId);
        // {
        //     uint256 longBasePaid = 355307653848063495604564433;
        //     uint256 shortAmount = 32781089323425741109202045220048496973701211100913991100118783234622240063487;
        //     _test_lp_withdrawal_three_lps(longBasePaid, shortAmount);
        // }
    }

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

        // Bob opens a long.
        testParams.longBasePaid = longBasePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong()
        );
        lpSharePrice = hyperdrive.lpSharePrice();
        (testParams.longMaturityTime, testParams.longAmount) = openLong(
            bob,
            testParams.longBasePaid
        );
        assertApproxEqAbs(hyperdrive.lpSharePrice(), lpSharePrice, 100);

        // Bob opens a short.
        lpSharePrice = hyperdrive.lpSharePrice();
        testParams.shortAmount = shortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxShort()
        );
        (testParams.shortMaturityTime, testParams.shortBasePaid) = openShort(
            bob,
            testParams.shortAmount
        );
        assertApproxEqAbs(hyperdrive.lpSharePrice(), lpSharePrice, 100);

        // Alice removes her liquidity.
        lpSharePrice = hyperdrive.lpSharePrice();
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Celine adds liquidity.
        lpSharePrice = hyperdrive.lpSharePrice();
        uint256 celineLpShares = addLiquidity(celine, testParams.contribution);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Bob closes as much of his long as possible.
        lpSharePrice = hyperdrive.lpSharePrice();
        closeLong(
            bob,
            testParams.longMaturityTime,
            testParams.longAmount.min(hyperdrive.calculateMaxShort())
        );
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Bob closes as much of his short as possible.
        lpSharePrice = hyperdrive.lpSharePrice();
        closeShort(
            bob,
            testParams.shortMaturityTime,
            testParams.shortAmount.min(hyperdrive.calculateMaxLong())
        );
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Redeem Alice's withdrawal shares. Alice should get at least the
        // margin released from Bob's long.
        lpSharePrice = hyperdrive.lpSharePrice();
        (uint256 aliceRedeemProceeds, ) = redeemWithdrawalShares(
            alice,
            aliceWithdrawalShares
        );
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);

        // Alice withdraws at least the original contribution.
        assertGe(
            aliceRedeemProceeds + aliceBaseProceeds,
            testParams.contribution
        );

        // FIXME: Make sure that all of the idle was paid out.
        //
        // Bob and Celine remove their liquidity. Bob should receive more base
        // proceeds than Celine since Celine's add liquidity resulted in an
        // increase in slippage for the outstanding positions.
        lpSharePrice = hyperdrive.lpSharePrice();
        (uint256 bobBaseProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);
        lpSharePrice = hyperdrive.lpSharePrice();
        (uint256 celineBaseProceeds, ) = removeLiquidity(
            celine,
            celineLpShares
        );
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e14)
        );
        assertLe(lpSharePrice, hyperdrive.lpSharePrice() + 100);
    }
}
