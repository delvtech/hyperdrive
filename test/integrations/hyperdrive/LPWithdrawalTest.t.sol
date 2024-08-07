// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdError } from "forge-std/StdError.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { LPMath } from "../../../contracts/src/libraries/LPMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract LPWithdrawalTest is HyperdriveTest {
    using FixedPointMath for int256;
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    // This is the maximum tolerance that we allow for the LP share price
    // changing in either direction.
    uint256 internal constant DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE = 1e10;

    // This is the maximum tolerance that we allow for the LP share price
    // decreasing.
    uint256 internal constant DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE = 1e6;

    function setUp() public override {
        super.setUp();

        // Deploy a Hyperdrive pool with the standard config and a 5% APR.
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
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

        // NOTE: If she removes all of her LP, Bob wouldn't be able to fully
        // close his long.
        //
        // Alice removes most of her LP shares. The LP share price should be
        // approximately equal before and after the transaction.
        (, uint256 withdrawalShares) = removeLiquidityWithChecks(
            alice,
            lpShares.mulDown(0.6e18)
        );

        // Bob closes his long. He will pay quite a bit of slippage on account
        // of the LP's removed liquidity. The LP share price should be
        // approximately equal before and after the transaction.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        closeLong(bob, maturityTime, longAmount);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(1e9)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

        // Alice removes her remaining LP shares. The LP share price should be
        // approximately equal before and after the transaction.
        (, uint256 withdrawalShares_) = removeLiquidityWithChecks(
            alice,
            lpShares - lpShares.mulDown(0.6e18)
        );
        withdrawalShares += withdrawalShares_;

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
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

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
                hyperdrive.getPoolInfo().vaultSharePrice +
                    hyperdrive.lpSharePrice()
            ),
            1e10
        );

        // Ensure that no withdrawal shares are ready for withdrawal and that
        // the present value of the outstanding withdrawal shares is zero. Most
        // of the time, all of the withdrawal shares will be completely paid out.
        // In some edge cases, the ending LP share price is small enough that
        // the present value of the withdrawal shares is zero, and they won't be
        // paid out.
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw, 0);
        assertApproxEqAbs(
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID).mulDown(
                hyperdrive.lpSharePrice()
            ),
            0,
            1
        );
    }

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

        // Alice removes all of her LP shares. The LP share price should be
        // approximately equal before and after the transaction, and the value
        // of her overall portfolio should be greater than or equal to her
        // original portfolio value.
        (, uint256 withdrawalShares) = removeLiquidityWithChecks(
            alice,
            lpShares
        );

        // Positive interest accrues over the term. We create a checkpoint for
        // the first checkpoint after opening the long to ensure that the
        // withdrawal shares will be accounted for properly.
        variableRate = variableRate.normalizeToRange(0, 2e18);
        advanceTime(CHECKPOINT_DURATION, variableRate);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);
        advanceTime(POSITION_DURATION - CHECKPOINT_DURATION, variableRate);

        // Bob closes his long. He should receive the full bond amount since he
        // is closing at maturity. The LP share price should be approximately
        // equal before and after the transaction.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        uint256 longProceeds = closeLong(bob, maturityTime, longAmount);
        assertLe(longProceeds, longAmount);
        assertApproxEqAbs(longProceeds, longAmount, 20);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            // NOTE: When the variable rate is low, the LP share price can drop
            // significantly since all of the LPs (except for address zero)
            // removed their liquidity. We lose precision in this regime, so we
            // need to be more lenient.
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE).max(
                DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE
            )
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
                lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
            );
            assertLe(
                lpSharePrice,
                hyperdrive.lpSharePrice() +
                    DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
            );

            // We expect Alice's withdrawal proceeds are greater than or equal
            // (with a fudge factor) to the amount predicted by the LP share
            // price.
            assertGe(
                withdrawalProceeds + 1e10,
                withdrawalShares.mulDown(lpSharePrice)
            );
        }

        // Ensure that the ending base balance of Hyperdrive only consists of
        // the minimum share reserves and address zero's LP shares.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().vaultSharePrice +
                    hyperdrive.lpSharePrice()
            ),
            1e10
        );

        // Ensure that no withdrawal shares are ready for withdrawal and that
        // the present value of the outstanding withdrawal shares is zero. Most
        // of the time, all of the withdrawal shares will be completely paid out.
        // In some edge cases, the ending LP share price is small enough that
        // the present value of the withdrawal shares is zero, and they won't be
        // paid out.
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw, 0);
        assertApproxEqAbs(
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID).mulDown(
                hyperdrive.lpSharePrice()
            ),
            0,
            1
        );
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

        // Alice removes all of her LP shares. The LP share price should be
        // conserved.
        removeLiquidityWithChecks(alice, lpShares);

        // Ensure that Bob can close his short. The system must always be able
        // to close the net short position to ensure that we don't enter a
        // regime where the present value can start increasing when liquidity
        // is removed.
        closeShort(bob, maturityTime, shortAmount);
    }

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

        // Alice removes all of her LP shares. She should recover her initial
        // contribution minus the amount of her capital that underlies Bob's
        // short position.
        (
            uint256 baseProceeds,
            uint256 withdrawalShares
        ) = removeLiquidityWithChecks(alice, lpShares);

        // Positive interest accrues over the term.
        variableRate = variableRate.normalizeToRange(0, 2e18);
        advanceTime(POSITION_DURATION, variableRate);

        // Bob closes his short. His proceeds should be the variable interest
        // that accrued on the short amount over the period.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
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
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

        // Alice redeems her withdrawal shares.
        lpSharePrice = hyperdrive.lpSharePrice();
        (uint256 withdrawalProceeds, ) = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

        // Ensure that Alice's proceeds are greater than or equal to her initial
        // contribution.
        assertGe(baseProceeds + withdrawalProceeds, contribution);

        // Ensure that the ending base balance of Hyperdrive only consists of
        // the minimum share reserves and address zero's LP shares.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().vaultSharePrice +
                    hyperdrive.lpSharePrice()
            ),
            1e10
        );

        // Ensure that no withdrawal shares are ready for withdrawal and that
        // the present value of the outstanding withdrawal shares is zero. Most
        // of the time, all of the withdrawal shares will be completely paid out.
        // In some edge cases, the ending LP share price is small enough that
        // the present value of the withdrawal shares is zero, and they won't be
        // paid out.
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw, 0);
        assertApproxEqAbs(
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID).mulDown(
                hyperdrive.lpSharePrice()
            ),
            0,
            1
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
        snapshotId = vm.snapshot();
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
        snapshotId = vm.snapshot();
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
        snapshotId = vm.snapshot();
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
        // This edge case results in the LP share price approaching zero
        // because the variable rate is close to zero and the net position is
        // entirely long.
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
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
        // This edge case results in some of the withdrawal shares not being
        // paid out because the ending LP share price is small enough that the
        // present value of the withdrawal shares is zero.
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        {
            uint256 longBasePaid = 11709480438780642195;
            uint256 shortAmount = 7116;
            int256 variableRate = 1334;
            _test_lp_withdrawal_long_and_short_maturity(
                longBasePaid,
                shortAmount,
                variableRate
            );
        }
        // This edge case results in the ending base balance being slightly more
        // than 1e9 larger than the expected value.
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        {
            uint256 longBasePaid = 340282366920938463456522083463006420839;
            uint256 shortAmount = 999999999884744250715574269;
            int256 variableRate = 4070;
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

        // Alice removes all of her LP shares. Ensure that the LP share price is
        // approximately equal after removing liquidity and that it is greater
        // than or equal to the previous LP share price.
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidityWithChecks(alice, aliceLpShares);

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
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        uint256 celineLpShares;
        vm.stopPrank();
        vm.startPrank(celine);
        baseToken.mint(testParams.contribution);
        baseToken.approve(address(hyperdrive), testParams.contribution);
        try
            hyperdrive.addLiquidity(
                testParams.contribution,
                0, // min lp share price
                0, // min spot rate
                type(uint256).max, // max spot rate
                IHyperdrive.Options({
                    destination: celine,
                    asBase: true,
                    extraData: new bytes(0)
                })
            )
        returns (uint256 lpShares_) {
            celineLpShares = lpShares_;
        } catch (bytes memory reason) {
            // Ensure that the error is a circuit breaker triggered error.
            assertTrue(
                reason.eq(
                    abi.encodeWithSelector(
                        IHyperdrive.CircuitBreakerTriggered.selector
                    )
                )
            );

            // Return since the test shouldn't continue without adding liquidity.
            return;
        }
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );
        int256 celineSlippagePayment = int256(testParams.contribution) -
            int256(celineLpShares.mulDown(lpSharePrice));
        assertGt(celineSlippagePayment, -1e10);

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
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

        // Celine removes all of her LP shares. She should recover her initial
        // contribution minus the amount of capital that underlies the short
        // and the long. Ensure that the LP share price is approximately equal
        // after removing liquidity  and that it is greater than or equal to the
        // previous LP share price.
        (
            uint256 celineBaseProceeds,
            uint256 celineWithdrawalShares
        ) = removeLiquidityWithChecks(celine, celineLpShares);

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
            // NOTE: When the variable rate is low, the LP share price can drop
            // significantly since all of the LPs (except for address zero)
            // removed their liquidity. We lose precision in this regime, so we
            // need to be more lenient.
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE).max(
                DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE
            )
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

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
                lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
            );
            assertLe(
                lpSharePrice,
                hyperdrive.lpSharePrice() +
                    DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
            );

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
                lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
            );
            assertLe(
                lpSharePrice,
                hyperdrive.lpSharePrice() +
                    DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
            );
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
                lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
            );
            assertLe(
                lpSharePrice,
                hyperdrive.lpSharePrice() +
                    DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
            );
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
                int256(testParams.contribution) -
                    celineSlippagePayment +
                    fixedInterest.min(0)
            )
        );

        // Ensure that the ending base balance of Hyperdrive only consists of
        // the minimum share reserves and address zero's LP shares.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().vaultSharePrice +
                    hyperdrive.lpSharePrice()
            ),
            1e10
        );

        // Ensure that no withdrawal shares are ready for withdrawal and that
        // the present value of the outstanding withdrawal shares is zero. Most
        // of the time, all of the withdrawal shares will be completely paid out.
        // In some edge cases, the ending LP share price is small enough that
        // the present value of the withdrawal shares is zero, and they won't be
        // paid out.
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw, 0);
        assertApproxEqAbs(
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID).mulDown(
                hyperdrive.lpSharePrice()
            ),
            0,
            1
        );
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
        snapshotId = vm.snapshot();
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
        snapshotId = vm.snapshot();
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
        snapshotId = vm.snapshot();
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
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidityWithChecks(alice, aliceLpShares);

        // Celine adds liquidity.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        uint256 celineLpShares;
        vm.stopPrank();
        vm.startPrank(celine);
        baseToken.mint(testParams.contribution);
        baseToken.approve(address(hyperdrive), testParams.contribution);
        try
            hyperdrive.addLiquidity(
                testParams.contribution,
                0, // min lp share price
                0, // min spot rate
                type(uint256).max, // max spot rate
                IHyperdrive.Options({
                    destination: celine,
                    asBase: true,
                    extraData: new bytes(0)
                })
            )
        returns (uint256 lpShares_) {
            celineLpShares = lpShares_;
        } catch (bytes memory reason) {
            // Ensure that the error is a circuit breaker triggered error.
            assertTrue(
                reason.eq(
                    abi.encodeWithSelector(
                        IHyperdrive.CircuitBreakerTriggered.selector
                    )
                )
            );

            // Return since the test shouldn't continue without adding liquidity.
            return;
        }
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

        // Redeem Alice's withdrawal shares. Alice should receive the margin
        // released from Bob's long as well as a payment for the additional
        // slippage incurred by Celine adding liquidity. She should be left with
        // no withdrawal shares.
        lpSharePrice = hyperdrive.lpSharePrice();
        (
            uint256 aliceRedeemProceeds,
            uint256 sharesRedeemed
        ) = redeemWithdrawalShares(alice, aliceWithdrawalShares);
        aliceWithdrawalShares -= sharesRedeemed;
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

        // Record the value of Alice's withdrawal shares after Celine adds
        // liquidity and Alice redeems some of her withdrawal shares.
        uint256 aliceWithdrawalSharesValueAfter = aliceWithdrawalShares.mulDown(
            hyperdrive.lpSharePrice()
        ) + aliceRedeemProceeds;

        // Ensure that the user expects to make at least as much money as
        // they put in.
        assertGe(
            aliceBaseProceeds + aliceWithdrawalSharesValueAfter,
            testParams.contribution
        );

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
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

        // Celine removes her liquidity.
        (, uint256 celineWithdrawalShares) = removeLiquidityWithChecks(
            celine,
            celineLpShares
        );

        // Time passes and interest accrues.
        testParams.variableRate = variableRate.normalizeToRange(0, 2e18);
        advanceTime(POSITION_DURATION, testParams.variableRate);

        // Bob closes his long.
        lpSharePrice = hyperdrive.lpSharePrice();
        closeLong(bob, testParams.longMaturityTime, testParams.longAmount);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            // NOTE: When the variable rate is low, the LP share price can drop
            // significantly since all of the LPs (except for address zero)
            // removed their liquidity. We lose precision in this regime, so
            // we need to be more lenient.
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE).max(
                DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE
            )
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

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
                // NOTE: When the variable rate is low, the LP share price can
                // drop significantly since all of the LPs (except for address
                // zero) removed their liquidity. We lose precision in this
                // regime, so we need to be more lenient.
                lpSharePrice
                    .mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
                    .max(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
            );
            assertLe(
                lpSharePrice,
                hyperdrive.lpSharePrice() +
                    DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
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
        }

        // Alice redeems her withdrawal shares.
        lpSharePrice = hyperdrive.lpSharePrice();
        redeemWithdrawalShares(alice, aliceWithdrawalShares);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

        // Celine redeems her withdrawal shares.
        lpSharePrice = hyperdrive.lpSharePrice();
        redeemWithdrawalShares(celine, celineWithdrawalShares);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

        // Ensure that the ending base balance of Hyperdrive only consists of
        // the minimum share reserves and address zero's LP shares.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().vaultSharePrice +
                    hyperdrive.lpSharePrice()
            ),
            1e10
        );

        // Ensure that no withdrawal shares are ready for withdrawal and that
        // the present value of the outstanding withdrawal shares is zero. Most
        // of the time, all of the withdrawal shares will be completely paid out.
        // In some edge cases, the ending LP share price is small enough that
        // the present value of the withdrawal shares is zero, and they won't be
        // paid out.
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw, 0);
        assertApproxEqAbs(
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID).mulDown(
                hyperdrive.lpSharePrice()
            ),
            0,
            1
        );
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
        (, uint256 aliceWithdrawalShares) = removeLiquidityWithChecks(
            alice,
            aliceLpShares
        );

        // Time passes and no interest accrues.
        advanceTime(POSITION_DURATION, 0);

        // Bob closes his long.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        closeLong(bob, testParams.longMaturityTime, testParams.longAmount);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

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
                lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
            );
            assertLe(
                lpSharePrice,
                hyperdrive.lpSharePrice() +
                    DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
            );
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
                lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
            );
            assertLe(
                lpSharePrice,
                hyperdrive.lpSharePrice() +
                    DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
            );
        }

        // Ensure that the ending base balance of Hyperdrive only consists of
        // the minimum share reserves and address zero's LP shares.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                hyperdrive.getPoolInfo().vaultSharePrice +
                    hyperdrive.lpSharePrice()
            ),
            1e10
        );

        // Ensure that no withdrawal shares are ready for withdrawal and that
        // the present value of the outstanding withdrawal shares is zero. Most
        // of the time, all of the withdrawal shares will be completely paid out.
        // In some edge cases, the ending LP share price is small enough that
        // the present value of the withdrawal shares is zero, and they won't be
        // paid out.
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw, 0);
        assertApproxEqAbs(
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID).mulDown(
                hyperdrive.lpSharePrice()
            ),
            0,
            1
        );
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
        snapshotId = vm.snapshot();
        {
            uint256 longBasePaid = 112173584723002853004121113797378997258679744955268467156471905609758801845023;
            uint256 shortAmount = 549812613265172043897083640351978971711251998278;
            _test_lp_withdrawal_three_lps(longBasePaid, shortAmount);
        }
        // This edge cases caused `calculateDistributeExcessIdle` to underflow.
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        {
            uint256 longBasePaid = 2;
            uint256 shortAmount = 87342192650471344091577440890542836777098066063815963805951289712;
            _test_lp_withdrawal_three_lps(longBasePaid, shortAmount);
        }
        // This edge case caused `addLiquidity` to underflow because the ending
        // present value is less than the starting present value. Upon closer
        // inspection, the short amount is 1.1 billion bonds and is 90 bonds
        // away from the max short. Not only would the LP not want to add
        // liquidity at this point, but traders would immediately start opening
        // profitable longs to rebalance the pool.
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        {
            uint256 longBasePaid = 4674632025073503415410714;
            uint256 shortAmount = 26193669303865160140313984349110751923066458523699888939112349;
            _test_lp_withdrawal_three_lps(longBasePaid, shortAmount);
        }
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
        assertApproxEqAbs(hyperdrive.lpSharePrice(), lpSharePrice, 1);

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
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidityWithChecks(alice, aliceLpShares);

        // Celine adds liquidity.
        lpSharePrice = hyperdrive.lpSharePrice();
        vm.stopPrank();
        vm.startPrank(celine);
        baseToken.mint(testParams.contribution);
        baseToken.approve(address(hyperdrive), testParams.contribution);
        uint256 celineLpShares;
        try
            hyperdrive.addLiquidity(
                testParams.contribution,
                0, // min lp share price of 0
                0, // min spot rate of 0
                type(uint256).max, // max spot rate of uint256 max
                IHyperdrive.Options({
                    destination: celine,
                    asBase: true,
                    extraData: new bytes(0) // unused
                })
            )
        returns (uint256 lpShares_) {
            celineLpShares = lpShares_;
        } catch (bytes memory reason) {
            // Ensure that the failure was caused by an arithmetic error.
            assertTrue(
                reason.eq(
                    abi.encodeWithSelector(
                        IHyperdrive
                            .DecreasedPresentValueWhenAddingLiquidity
                            .selector
                    )
                )
            );

            // In the event that the LP couldn't add liquidity, we should be
            // able to open a moderately sized long to rebalance the pool and
            // then add liquidity. In practice, the LP wouldn't even want to
            // add liquidity, and traders would immediately start opening
            // profitable longs to rebalance the pool.
            openLong(bob, 50_000e18);
            vm.stopPrank();
            vm.startPrank(celine);
            celineLpShares = hyperdrive.addLiquidity(
                testParams.contribution,
                0, // min lp share price of 0
                0, // min spot rate of 0
                type(uint256).max, // max spot rate of uint256 max
                IHyperdrive.Options({
                    destination: celine,
                    asBase: true,
                    extraData: new bytes(0) // unused
                })
            );
        }
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

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
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

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
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

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
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE)
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

        // Alice withdraws at least the original contribution.
        assertGe(
            aliceRedeemProceeds + aliceBaseProceeds,
            testParams.contribution
        );

        // Bob and Celine remove their liquidity. Bob should receive more base
        // proceeds than Celine since Celine's add liquidity resulted in an
        // increase in slippage for the outstanding positions.
        removeLiquidityWithChecks(bob, bobLpShares);
        removeLiquidityWithChecks(celine, celineLpShares);
    }

    function test_lp_withdrawal_negative_share_adjustment(
        uint256 preTradingLongBasePaid,
        int256 preTradingVariableRate,
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
        uint256 lpShares = initialize(
            alice,
            uint256(testParams.fixedRate),
            testParams.contribution
        );
        testParams.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Bob opens a long.
        preTradingLongBasePaid = preTradingLongBasePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong() / 2
        );
        openLong(bob, preTradingLongBasePaid);

        // The term advances and interest accrues.
        preTradingVariableRate = preTradingVariableRate.normalizeToRange(
            0.01e18,
            0.2e18
        );
        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a long.
        testParams.longBasePaid = longBasePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT * 2,
            hyperdrive.calculateMaxLong()
        );
        (testParams.longMaturityTime, testParams.longAmount) = openLong(
            bob,
            testParams.longBasePaid
        );

        // Bob opens a short.
        testParams.shortAmount = shortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxShort() - MINIMUM_TRANSACTION_AMOUNT
        );
        (testParams.shortMaturityTime, ) = openShort(
            bob,
            testParams.shortAmount
        );

        // Alice removes her liquidity.
        (, uint256 withdrawalShares) = removeLiquidityWithChecks(
            alice,
            lpShares
        );

        // The term advances and interest accrues.
        variableRate = variableRate.normalizeToRange(0.00001e18, 2e18);
        advanceTime(POSITION_DURATION, variableRate);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

        // Alice redeems her withdrawal shares.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        redeemWithdrawalShares(alice, withdrawalShares);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE).max(
                DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE
            )
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

        // Ensure that no withdrawal shares are ready for withdrawal and that
        // the present value of the outstanding withdrawal shares is zero. Most
        // of the time, all of the withdrawal shares will be completely paid out.
        // In some edge cases, the ending LP share price is small enough that
        // the present value of the withdrawal shares is zero, and they won't be
        // paid out.
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw, 0);
        assertApproxEqAbs(
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID).mulDown(
                hyperdrive.lpSharePrice()
            ),
            0,
            1
        );
    }

    function test_lp_withdrawal_positive_share_adjustment(
        uint256 preTradingShortAmount,
        int256 preTradingVariableRate,
        uint256 longBasePaid,
        uint256 shortAmount,
        int256 variableRate
    ) external {
        _test_lp_withdrawal_positive_share_adjustment(
            preTradingShortAmount,
            preTradingVariableRate,
            longBasePaid,
            shortAmount,
            variableRate
        );
    }

    function test_lp_withdrawal_positive_share_adjustment_edge_cases()
        external
    {
        // This edge case gets `calculateDistributeExcessIdleShareProceeds` into
        // the regime where it can solve directly for the share proceeds because
        // the share reserves are small enough that longs are being marked to 0.
        uint256 snapshotId = vm.snapshot();
        {
            uint256 preTradingShortAmount = 468068833135495314045336246;
            int256 preTradingVariableRate = 1695668740740805497720865;
            uint256 longBasePaid = 1010050167084247820;
            uint256 shortAmount = 5033;
            int256 variableRate = 13405;
            _test_lp_withdrawal_positive_share_adjustment(
                preTradingShortAmount,
                preTradingVariableRate,
                longBasePaid,
                shortAmount,
                variableRate
            );
        }
        // This edge cases results in the LP share price decreasing by more than
        // 100 wei and less than 1e6 wei. This is caused by the share price
        // itself decreasing by an amount on the order of 1e9 wei as a result of
        // roughly 500 million base being removed from the system in one go.
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        {
            uint256 preTradingShortAmount = 938;
            int256 preTradingVariableRate = 4099;
            uint256 longBasePaid = 14734;
            uint256 shortAmount = 1026527994858568917;
            int256 variableRate = 18520;
            _test_lp_withdrawal_positive_share_adjustment(
                preTradingShortAmount,
                preTradingVariableRate,
                longBasePaid,
                shortAmount,
                variableRate
            );
        }
    }

    function _test_lp_withdrawal_positive_share_adjustment(
        uint256 preTradingShortAmount,
        int256 preTradingVariableRate,
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
        uint256 lpShares = initialize(
            alice,
            uint256(testParams.fixedRate),
            testParams.contribution
        );
        testParams.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Bob opens a short.
        preTradingShortAmount = preTradingShortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxShort() / 2
        );
        openShort(bob, preTradingShortAmount);

        // The term advances and interest accrues.
        preTradingVariableRate = preTradingVariableRate.normalizeToRange(
            0.01e18,
            0.2e18
        );
        advanceTime(POSITION_DURATION, preTradingVariableRate);

        // Bob opens a long.
        testParams.longBasePaid = longBasePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT * 2,
            hyperdrive.calculateMaxLong()
        );
        (testParams.longMaturityTime, testParams.longAmount) = openLong(
            bob,
            testParams.longBasePaid
        );

        // Bob opens a short.
        testParams.shortAmount = shortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxShort()
        );
        (testParams.shortMaturityTime, ) = openShort(
            bob,
            testParams.shortAmount
        );

        // Alice removes her liquidity.
        (, uint256 withdrawalShares) = removeLiquidityWithChecks(
            alice,
            lpShares
        );

        // The term advances and interest accrues.
        variableRate = variableRate.normalizeToRange(0.00001e18, 2e18);
        advanceTime(POSITION_DURATION, variableRate);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

        // Alice redeems her withdrawal shares.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        redeemWithdrawalShares(alice, withdrawalShares);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE).max(
                DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE
            )
        );
        assertLe(
            lpSharePrice,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

        // Ensure that no withdrawal shares are ready for withdrawal and that
        // the present value of the outstanding withdrawal shares is zero. Most
        // of the time, all of the withdrawal shares will be completely paid out.
        // In some edge cases, the ending LP share price is small enough that
        // the present value of the withdrawal shares is zero, and they won't be
        // paid out.
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw, 0);
        assertApproxEqAbs(
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID).mulDown(
                hyperdrive.lpSharePrice()
            ),
            0,
            1
        );
    }

    // This test ensures that idle is distributed when zombie interest is
    // collected part of the way through a checkpoint after a long is closed.
    function test_lp_withdrawal_long_zombie_interest(
        uint256 contribution,
        uint256 fixedRate,
        int256 variableRate
    ) external {
        // Alice initializes the pool.
        contribution = contribution.normalizeToRange(
            1_000e18,
            1_000_000_000e18
        );
        // NOTE: A high fixed rate can lead to situations where idle can't
        // be distributed because the pool ends up in an extreme state of being
        // net short after the final short is opened. With this in mind, we cap
        // to 10% for the purpose of the test.
        fixedRate = fixedRate.normalizeToRange(0.01e18, 0.1e18);
        uint256 lpShares = initialize(alice, fixedRate, contribution);

        // Bob opens a large long.
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            hyperdrive.calculateMaxLong()
        );

        // The term passes and a checkpoint is minted.
        variableRate = variableRate.normalizeToRange(0.01e18, 0.2e18);
        advanceTime(POSITION_DURATION, variableRate);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

        // A large short is opened.
        //
        // NOTE: If the market ends up too net short, idle can't be distributed
        // due to an edge case. This is expected, but it would cause the test to
        // break since we expect idle to be distributed. To avoid this, we cap
        // the short amount to 80% of the maximum short amount.
        openShort(bob, hyperdrive.calculateMaxShort().mulDown(0.8e18));

        // Alice removes her liquidity.
        (, uint256 withdrawalShares) = removeLiquidityWithChecks(
            alice,
            lpShares
        );
        assertGt(withdrawalShares, 0);

        // Half a checkpoint passes and more interest accrues.
        advanceTime(CHECKPOINT_DURATION / 2, variableRate);

        // Bob closes his long.
        closeLong(bob, maturityTime, longAmount);

        // Alice attempts to redeem her withdrawal shares. Some of them should
        // be ready for withdrawal because of the zombie interest collected when
        // Bob's long was closed.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        (uint256 proceeds, uint256 sharesRedeemed) = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertGt(proceeds, 0);
        assertGt(sharesRedeemed, 0);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE).max(
                DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE
            )
        );
    }

    // This test ensures that idle is distributed when zombie interest is
    // collected part of the way through a checkpoint after a short is closed.
    function test_lp_withdrawal_short_zombie_interest(
        uint256 contribution,
        uint256 fixedRate,
        int256 variableRate
    ) external {
        // Alice initializes the pool.
        contribution = contribution.normalizeToRange(
            1_000_000e18,
            1_000_000_000e18
        );
        fixedRate = fixedRate.normalizeToRange(0.01e18, 0.2e18);
        uint256 lpShares = initialize(alice, fixedRate, contribution);

        // Bob opens a large short.
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // The term passes and a checkpoint is minted.
        variableRate = variableRate.normalizeToRange(0.01e18, 0.2e18);
        advanceTime(POSITION_DURATION, variableRate);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

        // A large long is opened.
        openLong(bob, hyperdrive.calculateMaxLong());

        // Alice removes her liquidity.
        (, uint256 withdrawalShares) = removeLiquidityWithChecks(
            alice,
            lpShares
        );
        assertGt(withdrawalShares, 0);

        // Half a checkpoint passes and more interest accrues.
        advanceTime(CHECKPOINT_DURATION / 2, variableRate);

        // Bob closes his short.
        closeShort(bob, maturityTime, shortAmount);

        // Alice attempts to redeem her withdrawal shares. Some of them should
        // be ready for withdrawal because of the zombie interest collected when
        // Bob's short was closed.
        uint256 lpSharePrice = hyperdrive.lpSharePrice();
        (uint256 proceeds, uint256 sharesRedeemed) = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertGt(proceeds, 0);
        assertGt(sharesRedeemed, 0);
        assertApproxEqAbs(
            lpSharePrice,
            hyperdrive.lpSharePrice(),
            lpSharePrice.mulDown(DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE).max(
                DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE
            )
        );
    }

    // This test verifies that the system's liveness isn't compromised by a
    // large LP removing liquidity and bringing the effective share reserves
    // below the minimum share reserves.
    function test_lp_withdrawal_liveness(
        uint256 contribution,
        uint256 fixedRate,
        int256 preRemovalVariableRate,
        int256 postRemovalVariableRate,
        uint256 basePaid
    ) external {
        // Alice initializes the pool.
        contribution = contribution.normalizeToRange(
            1_000e18,
            1_000_000_000e18
        );
        fixedRate = fixedRate.normalizeToRange(0.01e18, 0.2e18);
        uint256 lpShares = initialize(alice, fixedRate, contribution);

        // Bob opens a max short. This will maximally decrease the effective
        // share reserves.
        openShort(bob, hyperdrive.calculateMaxShort());

        // The term passes.
        preRemovalVariableRate = preRemovalVariableRate.normalizeToRange(
            0,
            2.5e18
        );
        advanceTime(POSITION_DURATION, preRemovalVariableRate);

        // Alice removes her liquidity.
        removeLiquidityWithChecks(alice, lpShares);

        // Advance the time to the next checkpoint and mint a checkpoint. This
        // ensures that checkpoint liveness hasn't been compromised.
        postRemovalVariableRate = postRemovalVariableRate.normalizeToRange(
            0,
            2.5e18
        );
        advanceTime(CHECKPOINT_DURATION, postRemovalVariableRate);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

        // Bob should be able to open a reasonably sized long despite the small
        // effective share reserves.
        basePaid = basePaid.normalizeToRange(
            2 * MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong()
        );
        openLong(bob, basePaid);
    }

    // This function removes liquidity and verifies that either (1) the maximum
    // amount of idle was distributed or (2) all of the withdrawal shares were
    // redeemed.
    function removeLiquidityWithChecks(
        address _lp,
        uint256 _lpShares
    ) internal returns (uint256, uint256) {
        // Get the maximum share reserves delta prior to removing liquidity.
        LPMath.DistributeExcessIdleParams memory params = hyperdrive
            .getDistributeExcessIdleParams();
        (uint256 maxShareReservesDelta, ) = LPMath
            .calculateMaxShareReservesDeltaSafe(
                params,
                HyperdriveMath.calculateEffectiveShareReserves(
                    params.originalShareReserves,
                    params.originalShareAdjustment
                )
            );
        uint256 maxBaseReservesDelta = maxShareReservesDelta.mulDown(
            hyperdrive.getPoolInfo().vaultSharePrice
        );

        // Remove the liquidity.
        uint256 idleBefore = hyperdrive.idle();
        uint256 readyToWithdraw = hyperdrive
            .getPoolInfo()
            .withdrawalSharesReadyToWithdraw;
        uint256 lpSharePriceBefore = hyperdrive.lpSharePrice();
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            _lp,
            _lpShares
        );

        // Ensure that the LP share price is within the tolerance.
        assertApproxEqAbs(
            lpSharePriceBefore,
            hyperdrive.lpSharePrice(),
            lpSharePriceBefore.mulDown(
                DISTRIBUTE_EXCESS_IDLE_ABSOLUTE_TOLERANCE
            )
        );
        assertLe(
            lpSharePriceBefore,
            hyperdrive.lpSharePrice() +
                DISTRIBUTE_EXCESS_IDLE_DECREASE_TOLERANCE
        );

        // Ensure that the system is solvent.
        assertGe(uint256(hyperdrive.solvency()), 0);

        // One of three things must be true. Either (1) we couldn't distribute
        // any of the excess idle due to numerical issues, (2) the max share
        // reserves delta was distributed or (2) all of the withdrawal shares
        // were redeemed.
        uint256 withdrawalSharesTotalSupply = hyperdrive.totalSupply(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID
        ) - hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw;
        if (
            withdrawalShares ==
            uint256((int256(_lpShares) - int256(readyToWithdraw))).max(0)
        ) {
            // Ensure that the pool's solvency is unchanged.
            assertEq(hyperdrive.idle(), idleBefore);
        } else if (withdrawalSharesTotalSupply > 0) {
            // Ensure that the max share reserves delta was distributed.
            assertApproxEqAbs(
                hyperdrive.idle(),
                idleBefore - maxBaseReservesDelta,
                1e11
            );
        } else {
            // The LP shouldn't receive withdrawal shares if all of the
            // withdrawal shares were marked ready for withdrawal.
            assertEq(withdrawalShares, 0);
        }

        return (baseProceeds, withdrawalShares);
    }
}
