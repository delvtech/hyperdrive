// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

// FIXME
import { console2 as console } from "forge-std/console2.sol";

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

// FIXME: We need to beef up the testing in several directions:
//
// 1. Fuzz with random trades (using the framework in the present value tests)
//    to ensure that the second LP always gets more in negative interest
//    scenarios.
// 2. Test checkpointing with gaps.
//
// FIXME: This should evolve into a test that verifies that we have consistent
// behavior with "Negative Interest Mode".
contract NegativeInterestLpTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using Lib for *;

    function test__negativeInterest__disabledWithinTolerance() external {
        // Negative interest within a checkpoint.
        _test__negativeInterest__disabledWithinTolerance(
            hyperdrive.getPoolConfig().checkpointDuration.mulDown(0.5e18)
        );

        // Negative interest at the checkpoint boundary.
        _test__negativeInterest__disabledWithinTolerance(
            hyperdrive.getPoolConfig().checkpointDuration
        );
    }

    function test__negativeInterest__disabledWithinTolerance__fuzz(
        uint256 _timeDelta
    ) external {
        uint256 checkpointDuration = hyperdrive
            .getPoolConfig()
            .checkpointDuration;
        _timeDelta = _timeDelta.normalizeToRange(
            checkpointDuration.mulDown(0.5e18),
            checkpointDuration.mulDown(1.99e18)
        );
        _test__negativeInterest__disabledWithinTolerance(_timeDelta);
    }

    // Tests that Hyperdrive ignores negative interest below the specified
    // tolerance.
    function _test__negativeInterest__disabledWithinTolerance(
        uint256 _timeDelta
    ) internal {
        // Alice deploys and initializes the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, testConfig(fixedRate));
        initialize(alice, fixedRate, contribution);

        // A tiny amount of negative interest accrues. If enough time has
        // elapsed, we will mint a checkpoint.
        uint256 sharePriceBefore = hyperdrive.getPoolInfo().sharePrice;
        advanceTime(
            _timeDelta,
            -int256(hyperdrive.getPoolConfig().negativeInterestTolerance)
        );
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // If enough time has passed, ensure that a new checkpoint was minted
        // with negative interest.
        if (_timeDelta > hyperdrive.getPoolConfig().checkpointDuration) {
            IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
                hyperdrive.latestCheckpoint()
            );
            assertGt(checkpoint.sharePrice, 0);
            assertLt(checkpoint.sharePrice, sharePriceBefore);
        }

        // Ensure that the negative interest reference share price and maturity
        // time weren't updated.
        IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
        assertEq(info.negativeInterestReferenceSharePrice, 0);
        assertEq(info.negativeInterestReferenceMaturityTime, 0);
    }

    function test__negativeInterest__enabledOutsideTolerance() external {
        // Negative interest within a checkpoint.
        _test__negativeInterest__enabledOutsideTolerance(
            hyperdrive.getPoolConfig().checkpointDuration.mulDown(0.5e18)
        );

        // Negative interest at the checkpoint boundary.
        _test__negativeInterest__enabledOutsideTolerance(
            hyperdrive.getPoolConfig().checkpointDuration
        );
    }

    function test__negativeInterest__enabledOutsideTolerance__fuzz(
        uint256 _timeDelta
    ) external {
        uint256 checkpointDuration = hyperdrive
            .getPoolConfig()
            .checkpointDuration;
        _timeDelta = _timeDelta.normalizeToRange(
            checkpointDuration.mulDown(0.5e18),
            checkpointDuration.mulDown(1.99e18)
        );
        _test__negativeInterest__enabledOutsideTolerance(_timeDelta);
    }

    // Tests that Hyperdrive records negative interest above the tolerance.
    function _test__negativeInterest__enabledOutsideTolerance(
        uint256 _timeDelta
    ) internal {
        // Alice deploys and initializes the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, testConfig(fixedRate));
        initialize(alice, fixedRate, contribution);

        // A small amount of negative interest accrues and a checkpoint is minted.
        uint256 sharePriceBefore = hyperdrive.getPoolInfo().sharePrice;
        uint256 checkpointTimeBefore = hyperdrive.latestCheckpoint();
        advanceTime(
            _timeDelta,
            -int256(hyperdrive.getPoolConfig().negativeInterestTolerance * 1000)
        );
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // If enough time has passed, ensure that the new checkpoint was minted
        // with negative interest.
        if (_timeDelta >= hyperdrive.getPoolConfig().checkpointDuration) {
            uint256 checkpointTime = hyperdrive.latestCheckpoint();
            IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
                checkpointTime
            );
            assertGt(checkpoint.sharePrice, 0);
            assertLt(checkpoint.sharePrice, sharePriceBefore);
        }

        // Ensure that the negative interest reference share price and maturity
        // time were updated. The reference share price should be set to the
        // share price from the starting checkpoint, and the reference maturity
        // time should be set to the maturity time of the starting checkpoint.
        IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
        assertEq(info.negativeInterestReferenceSharePrice, sharePriceBefore);
        assertEq(
            info.negativeInterestReferenceMaturityTime,
            checkpointTimeBefore + hyperdrive.getPoolConfig().positionDuration
        );
    }

    function test__negativeInterest__resetAtMaturity() external {
        // FIXME
    }

    // Tests that the negative interest reference share price and maturity time
    // are reset when a checkpoint is minted at or after the maturity time.
    function _test__negativeInterest__resetAtMaturity() internal {
        // FIXME
    }

    // FIXME: Test that negative interest is reset if a checkpoint share price
    // is higher than the reference price.

    // FIXME: Test that negative interest won't be reset if the share price goes
    // above the reference but isn't checkpointed.
    //
    // FIXME: As part of this, I should test that the present value isn't effected
    // by the share price for either long or short positions.

    // FIXME: Test accruing negative interest in several checkpoints. The max
    // share price and the maximum checkpoint ID should be used as the reference.
    // We'll need to test accruing negative interest in the past, and we should
    // test this in different scenarios.

    // FIXME: Test opening random trades and then verifying that the first LP to
    // withdraw always gets less than the second LP.

    // FIXME: Alice gets fucked in this one.
    function test_isolated_long_example() external {
        // Alice initializes the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, fixedRate, contribution);
        contribution -= 2 * hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine adds liquidity.
        uint256 celineLpShares = addLiquidity(celine, contribution);
        console.log(
            "lp balances: alice = %s, celine = %s",
            aliceLpShares.toString(18),
            celineLpShares.toString(18)
        );

        // Bob opens a long position.
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            hyperdrive.calculateMaxLong()
        );

        // Most of the term passes and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.99e18),
            -0.5e18
        );

        // Alice removes her LP.
        console.log(
            "before removeLiquidity: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);
        console.log(
            "after removeLiquidity: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );

        // Bob closes his long.
        console.log(
            "before closeLong: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );
        closeLong(bob, maturityTime, longAmount);
        console.log(
            "after closeLong: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );

        // Celine removes her LP.
        console.log(
            "before removeLiquidity: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );
        (
            uint256 celineBaseProceeds,
            uint256 celineWithdrawalShares
        ) = removeLiquidity(celine, celineLpShares);
        console.log(
            "after removeLiquidity: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );

        // Alice and Celine redeem their withdrawal shares.
        {
            (uint256 aliceWithdrawalProceeds, ) = redeemWithdrawalShares(
                alice,
                aliceWithdrawalShares
            );
            aliceBaseProceeds += aliceWithdrawalProceeds;
        }
        {
            (uint256 celineWithdrawalProceeds, ) = redeemWithdrawalShares(
                celine,
                celineWithdrawalShares
            );
            celineBaseProceeds += celineWithdrawalProceeds;
        }
        console.log(
            "lp proceeds: alice = %s, celine = %s",
            aliceBaseProceeds.toString(18),
            celineBaseProceeds.toString(18)
        );
    }

    // FIXME: Who gets fucked in this?
    function test_isolated_short_example() external {
        // Alice initializes the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, fixedRate, contribution);
        contribution -= 2 * hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine adds liquidity.
        uint256 celineLpShares = addLiquidity(celine, contribution);
        console.log(
            "lp balances: alice = %s, celine = %s",
            aliceLpShares.toString(18),
            celineLpShares.toString(18)
        );

        // Bob opens a long position.
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // Most of the term passes and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.99e18),
            -0.5e18
        );

        // Alice removes her LP.
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);
        console.log("aliceBaseProceeds = %s", aliceBaseProceeds.toString(18));

        // Bob closes his short.
        console.log(
            "before closeShort: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );
        closeShort(bob, maturityTime, shortAmount);
        console.log(
            "after closeShort: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );

        // Celine removes her LP.
        (
            uint256 celineBaseProceeds,
            uint256 celineWithdrawalShares
        ) = removeLiquidity(celine, celineLpShares);

        // Alice and Celine redeem their withdrawal shares.
        {
            (uint256 aliceWithdrawalProceeds, ) = redeemWithdrawalShares(
                alice,
                aliceWithdrawalShares
            );
            aliceBaseProceeds += aliceWithdrawalProceeds;
        }
        {
            (uint256 celineWithdrawalProceeds, ) = redeemWithdrawalShares(
                celine,
                celineWithdrawalShares
            );
            celineBaseProceeds += celineWithdrawalProceeds;
        }
        console.log(
            "lp proceeds: alice = %s, celine = %s",
            aliceBaseProceeds.toString(18),
            celineBaseProceeds.toString(18)
        );
    }

    struct TestCase {
        uint256 fixedRate;
        uint256 contribution;
        uint256 aliceLpShares;
        uint256 aliceBaseProceeds;
        uint256 aliceWithdrawalShares;
        uint256 celineLpShares;
        uint256 celineBaseProceeds;
        uint256 celineWithdrawalShares;
        uint256 maturityTime0;
        uint256 tradeAmount0;
        uint256 maturityTime1;
        uint256 tradeAmount1;
    }

    /// Long / Long Examples

    // FIXME: What is this telling us?
    function test_long_long_fifo_example() external {
        TestCase memory testCase = TestCase({
            fixedRate: 0.05e18,
            contribution: 500_000_000e18,
            aliceLpShares: 0,
            aliceBaseProceeds: 0,
            aliceWithdrawalShares: 0,
            celineLpShares: 0,
            celineBaseProceeds: 0,
            celineWithdrawalShares: 0,
            maturityTime0: 0,
            tradeAmount0: 0,
            maturityTime1: 0,
            tradeAmount1: 0
        });

        // Alice initializes the pool.
        testCase.aliceLpShares = initialize(
            alice,
            testCase.fixedRate,
            testCase.contribution
        );
        testCase.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine adds liquidity.
        testCase.celineLpShares = addLiquidity(celine, testCase.contribution);
        console.log(
            "lp balances: alice = %s, celine = %s",
            testCase.aliceLpShares.toString(18),
            testCase.celineLpShares.toString(18)
        );

        // Bob opens a long position.
        (testCase.maturityTime0, testCase.tradeAmount0) = openLong(
            bob,
            hyperdrive.calculateMaxLong() / 2
        );

        // A couple of checkpoints pass and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().checkpointDuration * 2,
            -0.5e18
        );

        // Bob opens another long position.
        (testCase.maturityTime1, testCase.tradeAmount1) = openLong(
            bob,
            hyperdrive.calculateMaxLong() / 2
        );

        // Most of the terms passes and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.99e18) -
                hyperdrive.getPoolConfig().checkpointDuration *
                2,
            -0.3e18
        );

        // Alice removes her LP.
        (
            testCase.aliceBaseProceeds,
            testCase.aliceWithdrawalShares
        ) = removeLiquidity(alice, testCase.aliceLpShares);

        // Bob closes his first long.
        closeLong(bob, testCase.maturityTime0, testCase.tradeAmount0);

        // Bob closes his second long.
        closeLong(bob, testCase.maturityTime1, testCase.tradeAmount1);

        // Celine removes her LP.
        (
            testCase.celineBaseProceeds,
            testCase.celineWithdrawalShares
        ) = removeLiquidity(celine, testCase.celineLpShares);

        // Alice and Celine redeem their withdrawal shares.
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(alice, testCase.aliceWithdrawalShares);
            testCase.aliceBaseProceeds += withdrawalProceeds;
            testCase.aliceWithdrawalShares -= sharesRedeemed;
        }
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(celine, testCase.celineWithdrawalShares);
            testCase.celineBaseProceeds += withdrawalProceeds;
            testCase.celineWithdrawalShares -= sharesRedeemed;
        }
        console.log(
            "lp proceeds: alice = %s, celine = %s",
            testCase.aliceBaseProceeds.toString(18),
            testCase.celineBaseProceeds.toString(18)
        );
    }

    // FIXME: What is this telling us?
    function test_long_long_lifo_example() external {
        TestCase memory testCase = TestCase({
            fixedRate: 0.05e18,
            contribution: 500_000_000e18,
            aliceLpShares: 0,
            aliceBaseProceeds: 0,
            aliceWithdrawalShares: 0,
            celineLpShares: 0,
            celineBaseProceeds: 0,
            celineWithdrawalShares: 0,
            maturityTime0: 0,
            tradeAmount0: 0,
            maturityTime1: 0,
            tradeAmount1: 0
        });

        // Alice initializes the pool.
        testCase.aliceLpShares = initialize(
            alice,
            testCase.fixedRate,
            testCase.contribution
        );
        testCase.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine adds liquidity.
        testCase.celineLpShares = addLiquidity(celine, testCase.contribution);
        console.log(
            "lp balances: alice = %s, celine = %s",
            testCase.aliceLpShares.toString(18),
            testCase.celineLpShares.toString(18)
        );

        // Bob opens a long position.
        (testCase.maturityTime0, testCase.tradeAmount0) = openLong(
            bob,
            hyperdrive.calculateMaxLong() / 2
        );

        // A couple of checkpoints pass and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().checkpointDuration * 2,
            -0.5e18
        );

        // Bob opens another long position.
        (testCase.maturityTime1, testCase.tradeAmount1) = openLong(
            bob,
            hyperdrive.calculateMaxLong() / 2
        );

        // Most of the terms passes and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.99e18) -
                hyperdrive.getPoolConfig().checkpointDuration *
                2,
            -0.3e18
        );

        // Alice removes her LP.
        (
            testCase.aliceBaseProceeds,
            testCase.aliceWithdrawalShares
        ) = removeLiquidity(alice, testCase.aliceLpShares);

        // Bob closes his second long.
        closeLong(bob, testCase.maturityTime1, testCase.tradeAmount1);

        // Bob closes his first long.
        closeLong(bob, testCase.maturityTime0, testCase.tradeAmount0);

        // Celine removes her LP.
        (
            testCase.celineBaseProceeds,
            testCase.celineWithdrawalShares
        ) = removeLiquidity(celine, testCase.celineLpShares);

        // Alice and Celine redeem their withdrawal shares.
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(alice, testCase.aliceWithdrawalShares);
            testCase.aliceBaseProceeds += withdrawalProceeds;
            testCase.aliceWithdrawalShares -= sharesRedeemed;
        }
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(celine, testCase.celineWithdrawalShares);
            testCase.celineBaseProceeds += withdrawalProceeds;
            testCase.celineWithdrawalShares -= sharesRedeemed;
        }
        console.log(
            "lp proceeds: alice = %s, celine = %s",
            testCase.aliceBaseProceeds.toString(18),
            testCase.celineBaseProceeds.toString(18)
        );
    }

    /// Long / Short Examples

    // FIXME: What is this telling us?
    function test_long_short_fifo_example() external {
        TestCase memory testCase = TestCase({
            fixedRate: 0.05e18,
            contribution: 500_000_000e18,
            aliceLpShares: 0,
            aliceBaseProceeds: 0,
            aliceWithdrawalShares: 0,
            celineLpShares: 0,
            celineBaseProceeds: 0,
            celineWithdrawalShares: 0,
            maturityTime0: 0,
            tradeAmount0: 0,
            maturityTime1: 0,
            tradeAmount1: 0
        });

        // Alice initializes the pool.
        testCase.aliceLpShares = initialize(
            alice,
            testCase.fixedRate,
            testCase.contribution
        );
        testCase.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine adds liquidity.
        testCase.celineLpShares = addLiquidity(celine, testCase.contribution);
        console.log(
            "lp balances: alice = %s, celine = %s",
            testCase.aliceLpShares.toString(18),
            testCase.celineLpShares.toString(18)
        );

        // Bob opens a long position.
        (testCase.maturityTime0, testCase.tradeAmount0) = openLong(
            bob,
            hyperdrive.calculateMaxLong() / 2
        );

        // A couple of checkpoints pass and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().checkpointDuration * 2,
            -0.5e18
        );

        // Bob opens a short position.
        testCase.tradeAmount1 = hyperdrive.calculateMaxShort() / 2;
        (testCase.maturityTime1, ) = openShort(bob, testCase.tradeAmount1);

        // Most of the terms passes and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.99e18) -
                hyperdrive.getPoolConfig().checkpointDuration *
                2,
            -0.3e18
        );

        // Alice removes her LP.
        (
            testCase.aliceBaseProceeds,
            testCase.aliceWithdrawalShares
        ) = removeLiquidity(alice, testCase.aliceLpShares);

        // Bob closes his long.
        closeLong(bob, testCase.maturityTime0, testCase.tradeAmount0);

        // Bob closes his short.
        closeShort(bob, testCase.maturityTime1, testCase.tradeAmount1);

        // Celine removes her LP.
        (
            testCase.celineBaseProceeds,
            testCase.celineWithdrawalShares
        ) = removeLiquidity(celine, testCase.celineLpShares);

        // Alice and Celine redeem their withdrawal shares.
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(alice, testCase.aliceWithdrawalShares);
            testCase.aliceBaseProceeds += withdrawalProceeds;
            testCase.aliceWithdrawalShares -= sharesRedeemed;
        }
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(celine, testCase.celineWithdrawalShares);
            testCase.celineBaseProceeds += withdrawalProceeds;
            testCase.celineWithdrawalShares -= sharesRedeemed;
        }
        console.log(
            "lp proceeds: alice = %s, celine = %s",
            testCase.aliceBaseProceeds.toString(18),
            testCase.celineBaseProceeds.toString(18)
        );
    }

    // FIXME: What is this telling us?
    function test_long_short_lifo_example() external {
        TestCase memory testCase = TestCase({
            fixedRate: 0.05e18,
            contribution: 500_000_000e18,
            aliceLpShares: 0,
            aliceBaseProceeds: 0,
            aliceWithdrawalShares: 0,
            celineLpShares: 0,
            celineBaseProceeds: 0,
            celineWithdrawalShares: 0,
            maturityTime0: 0,
            tradeAmount0: 0,
            maturityTime1: 0,
            tradeAmount1: 0
        });

        // Alice initializes the pool.
        testCase.aliceLpShares = initialize(
            alice,
            testCase.fixedRate,
            testCase.contribution
        );
        testCase.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine adds liquidity.
        testCase.celineLpShares = addLiquidity(celine, testCase.contribution);
        console.log(
            "lp balances: alice = %s, celine = %s",
            testCase.aliceLpShares.toString(18),
            testCase.celineLpShares.toString(18)
        );

        // Bob opens a long position.
        (testCase.maturityTime0, testCase.tradeAmount0) = openLong(
            bob,
            hyperdrive.calculateMaxLong() / 2
        );

        // A couple of checkpoints pass and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().checkpointDuration * 2,
            -0.5e18
        );

        // Bob opens a short position.
        testCase.tradeAmount1 = hyperdrive.calculateMaxShort() / 2;
        (testCase.maturityTime1, ) = openShort(bob, testCase.tradeAmount1);

        // Most of the terms passes and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.99e18) -
                hyperdrive.getPoolConfig().checkpointDuration *
                2,
            -0.3e18
        );

        // Alice removes her LP.
        (
            testCase.aliceBaseProceeds,
            testCase.aliceWithdrawalShares
        ) = removeLiquidity(alice, testCase.aliceLpShares);

        // Bob closes his short.
        closeShort(bob, testCase.maturityTime1, testCase.tradeAmount1);

        // Bob closes his long.
        closeLong(bob, testCase.maturityTime0, testCase.tradeAmount0);

        // Celine removes her LP.
        (
            testCase.celineBaseProceeds,
            testCase.celineWithdrawalShares
        ) = removeLiquidity(celine, testCase.celineLpShares);

        // Alice and Celine redeem their withdrawal shares.
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(alice, testCase.aliceWithdrawalShares);
            testCase.aliceBaseProceeds += withdrawalProceeds;
            testCase.aliceWithdrawalShares -= sharesRedeemed;
        }
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(celine, testCase.celineWithdrawalShares);
            testCase.celineBaseProceeds += withdrawalProceeds;
            testCase.celineWithdrawalShares -= sharesRedeemed;
        }
        console.log(
            "lp proceeds: alice = %s, celine = %s",
            testCase.aliceBaseProceeds.toString(18),
            testCase.celineBaseProceeds.toString(18)
        );
    }

    /// Short / Short Examples

    // FIXME: What is this telling us?
    function test_short_short_fifo_example() external {
        TestCase memory testCase = TestCase({
            fixedRate: 0.05e18,
            contribution: 500_000_000e18,
            aliceLpShares: 0,
            aliceBaseProceeds: 0,
            aliceWithdrawalShares: 0,
            celineLpShares: 0,
            celineBaseProceeds: 0,
            celineWithdrawalShares: 0,
            maturityTime0: 0,
            tradeAmount0: 0,
            maturityTime1: 0,
            tradeAmount1: 0
        });

        // Alice initializes the pool.
        testCase.aliceLpShares = initialize(
            alice,
            testCase.fixedRate,
            testCase.contribution
        );
        testCase.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine adds liquidity.
        testCase.celineLpShares = addLiquidity(celine, testCase.contribution);
        console.log(
            "lp balances: alice = %s, celine = %s",
            testCase.aliceLpShares.toString(18),
            testCase.celineLpShares.toString(18)
        );

        // Bob opens a short position.
        testCase.tradeAmount0 = hyperdrive.calculateMaxShort() / 2;
        (testCase.maturityTime0, ) = openShort(bob, testCase.tradeAmount0);

        // A couple of checkpoints pass and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().checkpointDuration * 2,
            -0.5e18
        );

        // Bob opens a short position.
        testCase.tradeAmount1 = hyperdrive.calculateMaxShort() / 2;
        (testCase.maturityTime1, ) = openShort(bob, testCase.tradeAmount1);

        // Most of the terms passes and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.99e18) -
                hyperdrive.getPoolConfig().checkpointDuration *
                2,
            -0.3e18
        );

        // Alice removes her LP.
        (
            testCase.aliceBaseProceeds,
            testCase.aliceWithdrawalShares
        ) = removeLiquidity(alice, testCase.aliceLpShares);

        // Bob closes his first short.
        closeShort(bob, testCase.maturityTime0, testCase.tradeAmount0);

        // Bob closes his second short.
        closeShort(bob, testCase.maturityTime1, testCase.tradeAmount1);

        // Celine removes her LP.
        (
            testCase.celineBaseProceeds,
            testCase.celineWithdrawalShares
        ) = removeLiquidity(celine, testCase.celineLpShares);

        // Alice and Celine redeem their withdrawal shares.
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(alice, testCase.aliceWithdrawalShares);
            testCase.aliceBaseProceeds += withdrawalProceeds;
            testCase.aliceWithdrawalShares -= sharesRedeemed;
        }
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(celine, testCase.celineWithdrawalShares);
            testCase.celineBaseProceeds += withdrawalProceeds;
            testCase.celineWithdrawalShares -= sharesRedeemed;
        }
        console.log(
            "lp proceeds: alice = %s, celine = %s",
            testCase.aliceBaseProceeds.toString(18),
            testCase.celineBaseProceeds.toString(18)
        );
    }

    // FIXME: What is this telling us?
    function test_short_short_lifo_example() external {
        TestCase memory testCase = TestCase({
            fixedRate: 0.05e18,
            contribution: 500_000_000e18,
            aliceLpShares: 0,
            aliceBaseProceeds: 0,
            aliceWithdrawalShares: 0,
            celineLpShares: 0,
            celineBaseProceeds: 0,
            celineWithdrawalShares: 0,
            maturityTime0: 0,
            tradeAmount0: 0,
            maturityTime1: 0,
            tradeAmount1: 0
        });

        // Alice initializes the pool.
        testCase.aliceLpShares = initialize(
            alice,
            testCase.fixedRate,
            testCase.contribution
        );
        testCase.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine adds liquidity.
        testCase.celineLpShares = addLiquidity(celine, testCase.contribution);
        console.log(
            "lp balances: alice = %s, celine = %s",
            testCase.aliceLpShares.toString(18),
            testCase.celineLpShares.toString(18)
        );

        // Bob opens a short position.
        testCase.tradeAmount0 = hyperdrive.calculateMaxLong() / 2;
        (testCase.maturityTime0, ) = openShort(bob, testCase.tradeAmount0);

        // A couple of checkpoints pass and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().checkpointDuration * 2,
            -0.5e18
        );

        // Bob opens a short position.
        testCase.tradeAmount1 = hyperdrive.calculateMaxShort() / 2;
        (testCase.maturityTime1, ) = openShort(bob, testCase.tradeAmount1);

        // Most of the terms passes and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.99e18) -
                hyperdrive.getPoolConfig().checkpointDuration *
                2,
            -0.3e18
        );

        // Alice removes her LP.
        console.log(
            "before removeLiquidity: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );
        (
            testCase.aliceBaseProceeds,
            testCase.aliceWithdrawalShares
        ) = removeLiquidity(alice, testCase.aliceLpShares);
        console.log(
            "after removeLiquidity: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );

        // Bob closes his second short.
        console.log(
            "before closeShort: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );
        closeShort(bob, testCase.maturityTime1, testCase.tradeAmount1);
        console.log(
            "after closeShort: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );

        // Bob closes his first short.
        console.log(
            "before closeShort: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );
        closeShort(bob, testCase.maturityTime0, testCase.tradeAmount0);
        console.log(
            "after closeShort: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );

        // Celine removes her LP.
        console.log(
            "before removeLiquidity: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );
        (
            testCase.celineBaseProceeds,
            testCase.celineWithdrawalShares
        ) = removeLiquidity(celine, testCase.celineLpShares);
        console.log(
            "after removeLiquidity: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );

        // Alice and Celine redeem their withdrawal shares.
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(alice, testCase.aliceWithdrawalShares);
            testCase.aliceBaseProceeds += withdrawalProceeds;
            testCase.aliceWithdrawalShares -= sharesRedeemed;
        }
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(celine, testCase.celineWithdrawalShares);
            testCase.celineBaseProceeds += withdrawalProceeds;
            testCase.celineWithdrawalShares -= sharesRedeemed;
        }
        console.log(
            "lp proceeds: alice = %s, celine = %s",
            testCase.aliceBaseProceeds.toString(18),
            testCase.celineBaseProceeds.toString(18)
        );
    }

    /// Short / Long Examples

    // FIXME: What is this telling us?
    function test_short_long_fifo_example() external {
        TestCase memory testCase = TestCase({
            fixedRate: 0.05e18,
            contribution: 500_000_000e18,
            aliceLpShares: 0,
            aliceBaseProceeds: 0,
            aliceWithdrawalShares: 0,
            celineLpShares: 0,
            celineBaseProceeds: 0,
            celineWithdrawalShares: 0,
            maturityTime0: 0,
            tradeAmount0: 0,
            maturityTime1: 0,
            tradeAmount1: 0
        });

        // Alice initializes the pool.
        testCase.aliceLpShares = initialize(
            alice,
            testCase.fixedRate,
            testCase.contribution
        );
        testCase.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine adds liquidity.
        testCase.celineLpShares = addLiquidity(celine, testCase.contribution);
        console.log(
            "lp balances: alice = %s, celine = %s",
            testCase.aliceLpShares.toString(18),
            testCase.celineLpShares.toString(18)
        );

        // Bob opens a short position.
        testCase.tradeAmount0 = hyperdrive.calculateMaxShort() / 2;
        (testCase.maturityTime0, ) = openShort(bob, testCase.tradeAmount0);

        // A couple of checkpoints pass and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().checkpointDuration * 2,
            -0.5e18
        );

        // Bob opens a long position.
        (testCase.maturityTime1, testCase.tradeAmount1) = openLong(
            bob,
            hyperdrive.calculateMaxLong() / 2
        );

        // Most of the terms passes and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.99e18) -
                hyperdrive.getPoolConfig().checkpointDuration *
                2,
            -0.3e18
        );

        // Alice removes her LP.
        (
            testCase.aliceBaseProceeds,
            testCase.aliceWithdrawalShares
        ) = removeLiquidity(alice, testCase.aliceLpShares);

        // Bob closes his short.
        closeShort(bob, testCase.maturityTime0, testCase.tradeAmount0);

        // Bob closes his long.
        closeLong(bob, testCase.maturityTime1, testCase.tradeAmount1);

        // Celine removes her LP.
        (
            testCase.celineBaseProceeds,
            testCase.celineWithdrawalShares
        ) = removeLiquidity(celine, testCase.celineLpShares);

        // Alice and Celine redeem their withdrawal shares.
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(alice, testCase.aliceWithdrawalShares);
            testCase.aliceBaseProceeds += withdrawalProceeds;
            testCase.aliceWithdrawalShares -= sharesRedeemed;
        }
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(celine, testCase.celineWithdrawalShares);
            testCase.celineBaseProceeds += withdrawalProceeds;
            testCase.celineWithdrawalShares -= sharesRedeemed;
        }
        console.log(
            "lp proceeds: alice = %s, celine = %s",
            testCase.aliceBaseProceeds.toString(18),
            testCase.celineBaseProceeds.toString(18)
        );
    }

    // FIXME: What is this telling us?
    function test_short_long_lifo_example() external {
        TestCase memory testCase = TestCase({
            fixedRate: 0.05e18,
            contribution: 500_000_000e18,
            aliceLpShares: 0,
            aliceBaseProceeds: 0,
            aliceWithdrawalShares: 0,
            celineLpShares: 0,
            celineBaseProceeds: 0,
            celineWithdrawalShares: 0,
            maturityTime0: 0,
            tradeAmount0: 0,
            maturityTime1: 0,
            tradeAmount1: 0
        });

        // Alice initializes the pool.
        testCase.aliceLpShares = initialize(
            alice,
            testCase.fixedRate,
            testCase.contribution
        );
        testCase.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine adds liquidity.
        testCase.celineLpShares = addLiquidity(celine, testCase.contribution);
        console.log(
            "lp balances: alice = %s, celine = %s",
            testCase.aliceLpShares.toString(18),
            testCase.celineLpShares.toString(18)
        );

        // Bob opens a short position.
        testCase.tradeAmount0 = hyperdrive.calculateMaxLong() / 2;
        (testCase.maturityTime0, ) = openShort(bob, testCase.tradeAmount0);

        // A couple of checkpoints pass and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().checkpointDuration * 2,
            -0.5e18
        );

        // Bob opens a long position.
        (testCase.maturityTime1, testCase.tradeAmount1) = openLong(
            bob,
            hyperdrive.calculateMaxLong() / 2
        );

        // Most of the terms passes and negative interest accrues.
        advanceTimeWithCheckpoints(
            hyperdrive.getPoolConfig().positionDuration.mulDown(0.99e18) -
                hyperdrive.getPoolConfig().checkpointDuration *
                2,
            -0.3e18
        );

        // Alice removes her LP.
        console.log(
            "before removeLiquidity: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );
        (
            testCase.aliceBaseProceeds,
            testCase.aliceWithdrawalShares
        ) = removeLiquidity(alice, testCase.aliceLpShares);
        console.log(
            "after removeLiquidity: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );

        // Bob closes his long.
        console.log(
            "before closeLong: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );
        closeLong(bob, testCase.maturityTime1, testCase.tradeAmount1);
        console.log(
            "after closeLong: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );

        // Bob closes his short.
        console.log(
            "before closeShort: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );
        closeShort(bob, testCase.maturityTime0, testCase.tradeAmount0);
        console.log(
            "after closeShort: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );

        // Celine removes her LP.
        console.log(
            "before removeLiquidity: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );
        (
            testCase.celineBaseProceeds,
            testCase.celineWithdrawalShares
        ) = removeLiquidity(celine, testCase.celineLpShares);
        console.log(
            "after removeLiquidity: lpSharePrice = %s",
            hyperdrive.lpSharePrice().toString(18)
        );

        // Alice and Celine redeem their withdrawal shares.
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(alice, testCase.aliceWithdrawalShares);
            testCase.aliceBaseProceeds += withdrawalProceeds;
            testCase.aliceWithdrawalShares -= sharesRedeemed;
        }
        {
            (
                uint256 withdrawalProceeds,
                uint256 sharesRedeemed
            ) = redeemWithdrawalShares(celine, testCase.celineWithdrawalShares);
            testCase.celineBaseProceeds += withdrawalProceeds;
            testCase.celineWithdrawalShares -= sharesRedeemed;
        }
        console.log(
            "lp proceeds: alice = %s, celine = %s",
            testCase.aliceBaseProceeds.toString(18),
            testCase.celineBaseProceeds.toString(18)
        );
    }
}
