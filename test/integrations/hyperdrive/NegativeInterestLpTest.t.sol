// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract NegativeInterestLpTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using Lib for *;

    // Tests that Hyperdrive ignores negative interest below the specified
    // tolerance.
    function test__negativeInterest__disabledWithinTolerance(
        uint256 _timeDelta
    ) external {
        // Alice deploys and initializes the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, testConfig(fixedRate));
        initialize(alice, fixedRate, contribution);

        // Sample a time delta that is between 50% and 199% of a checkpoint.
        // This range is chosen because it includes at most one checkpoint and
        // won't result in negative interest large enough to be recorded at our
        // interest rate.
        uint256 checkpointDuration = hyperdrive
            .getPoolConfig()
            .checkpointDuration;
        _timeDelta = _timeDelta.normalizeToRange(
            checkpointDuration.mulDown(0.5e18),
            checkpointDuration.mulDown(1.99e18)
        );

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
        if (_timeDelta >= checkpointDuration) {
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

    // Tests that Hyperdrive records negative interest above the tolerance.
    function test__negativeInterest__enabledOutsideTolerance(
        uint256 _timeDelta
    ) external {
        // Alice deploys and initializes the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, testConfig(fixedRate));
        initialize(alice, fixedRate, contribution);

        // Sample a time delta that is between 50% and 199% of a checkpoint.
        // This range is chosen because it includes at most one checkpoint and
        // will result in negative interest large enough to be recorded at our
        // interest rate.
        uint256 checkpointDuration = hyperdrive
            .getPoolConfig()
            .checkpointDuration;
        _timeDelta = _timeDelta.normalizeToRange(
            checkpointDuration.mulDown(0.5e18),
            checkpointDuration.mulDown(1.99e18)
        );

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
        if (_timeDelta >= checkpointDuration) {
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

    // Tests that the negative interest reference share price and maturity time
    // are reset when a checkpoint is minted at or after the maturity time.
    function test__negativeInterest__resetAtMaturity(
        uint256 _timeDelta0,
        uint256 _timeDelta1
    ) external {
        // Alice deploys and initializes the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, testConfig(fixedRate));
        initialize(alice, fixedRate, contribution);

        // Sample two time deltas that add up to at least the position duration.
        uint256 checkpointDuration = hyperdrive
            .getPoolConfig()
            .checkpointDuration;
        uint256 positionDuration = hyperdrive.getPoolConfig().positionDuration;
        _timeDelta0 = _timeDelta0.normalizeToRange(
            checkpointDuration.mulDown(0.5e18),
            checkpointDuration.mulDown(1.99e18)
        );
        _timeDelta1 = _timeDelta1.normalizeToRange(
            positionDuration - _timeDelta0,
            2 * positionDuration
        );

        // A small amount of negative interest accrues and a checkpoint is minted.
        uint256 sharePriceBefore = hyperdrive.getPoolInfo().sharePrice;
        uint256 checkpointTimeBefore = hyperdrive.latestCheckpoint();
        advanceTime(
            _timeDelta0,
            -int256(hyperdrive.getPoolConfig().negativeInterestTolerance * 1000)
        );
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

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

        // A long time passes with no interest accrual and a checkpoint is minted.
        advanceTime(_timeDelta1, 0);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Ensure that the negative interest reference share price and maturity
        // time were reset.
        info = hyperdrive.getPoolInfo();
        assertEq(info.negativeInterestReferenceSharePrice, 0);
        assertEq(info.negativeInterestReferenceMaturityTime, 0);
    }

    // Tests that the negative interest reference share price and maturity time
    // are not reset when the share price spikes above the reference between
    // checkpoints. If we reset the reference, it's possible that negative
    // interest could accrue again with an invalid reference share price.
    function test__negativeInterest__notResetWhenSharePriceExceedsReference(
        uint256 _timeDelta
    ) external {
        // Alice deploys and initializes the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, testConfig(fixedRate));
        initialize(alice, fixedRate, contribution);

        // Sample a time delta that is less than two checkpoints.
        uint256 checkpointDuration = hyperdrive
            .getPoolConfig()
            .checkpointDuration;
        _timeDelta = _timeDelta.normalizeToRange(
            checkpointDuration.mulDown(0.5e18),
            checkpointDuration.mulDown(1.5e18)
        );

        // A small amount of negative interest accrues and a checkpoint is minted.
        uint256 sharePriceBefore = hyperdrive.getPoolInfo().sharePrice;
        uint256 checkpointTimeBefore = hyperdrive.latestCheckpoint();
        advanceTime(
            _timeDelta,
            -int256(hyperdrive.getPoolConfig().negativeInterestTolerance * 1000)
        );
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

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

        // The share price spikes above the starting point (because of a very
        // generous donation) and we attempt to mint a checkpoint. Not enough
        // time has passed, so a new checkpoint isn't minted Despite the share
        // price being larger than the reference share price, the reference
        // share price and maturity time are not reset.
        baseToken.mint(
            address(hyperdrive),
            baseToken.balanceOf(address(hyperdrive))
        );
        assertGt(
            hyperdrive.getPoolInfo().sharePrice,
            info.negativeInterestReferenceMaturityTime
        );
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());
        info = hyperdrive.getPoolInfo();
        assertGt(info.negativeInterestReferenceSharePrice, 0);
        assertGt(info.negativeInterestReferenceMaturityTime, 0);
    }

    // Tests that the negative interest reference share price and maturity time
    // are reset when a newly minted checkpoint share price exceeds the reference.
    function test__negativeInterest__resetWhenCheckpointSharePriceExceedsReference(
        uint256 _timeDelta
    ) external {
        // Alice deploys and initializes the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, testConfig(fixedRate));
        initialize(alice, fixedRate, contribution);

        // Sample a time delta that is less than two checkpoints.
        uint256 checkpointDuration = hyperdrive
            .getPoolConfig()
            .checkpointDuration;
        _timeDelta = _timeDelta.normalizeToRange(
            checkpointDuration.mulDown(0.5e18),
            checkpointDuration.mulDown(1.5e18)
        );

        // A small amount of negative interest accrues and a checkpoint is minted.
        uint256 sharePriceBefore = hyperdrive.getPoolInfo().sharePrice;
        uint256 checkpointTimeBefore = hyperdrive.latestCheckpoint();
        advanceTime(
            _timeDelta,
            -int256(hyperdrive.getPoolConfig().negativeInterestTolerance * 1000)
        );
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

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

        // The share price spikes above the starting point (because of a very
        // generous donation) and enough time passes that a new checkpoint can
        // be minted successfully. Ensure that the reference share price and
        // maturity time are reset.
        baseToken.mint(
            address(hyperdrive),
            baseToken.balanceOf(address(hyperdrive))
        );
        assertGt(
            hyperdrive.getPoolInfo().sharePrice,
            info.negativeInterestReferenceMaturityTime
        );
        advanceTime(checkpointDuration, 0);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());
        info = hyperdrive.getPoolInfo();
        assertEq(info.negativeInterestReferenceSharePrice, 0);
        assertEq(info.negativeInterestReferenceMaturityTime, 0);
    }

    // Tests that scenario in which negative interest accrues and is recorded,
    // and then another checkpoint of negative interest elapses.
    function test__negativeInterest__subsequentCheckpoints(
        uint256 _timeDelta
    ) external {
        // Alice deploys and initializes the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, testConfig(fixedRate));
        initialize(alice, fixedRate, contribution);

        // Sample a time delta that is less than two checkpoints.
        uint256 checkpointDuration = hyperdrive
            .getPoolConfig()
            .checkpointDuration;
        _timeDelta = _timeDelta.normalizeToRange(
            checkpointDuration.mulDown(0.5e18),
            checkpointDuration.mulDown(1.5e18)
        );

        // A small amount of negative interest accrues and a checkpoint is minted.
        uint256 sharePriceBefore = hyperdrive.getPoolInfo().sharePrice;
        uint256 checkpointTimeBefore = hyperdrive.latestCheckpoint();
        advanceTime(
            _timeDelta,
            -int256(hyperdrive.getPoolConfig().negativeInterestTolerance * 1000)
        );
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Ensure that the negative interest reference share price and maturity
        // time were updated. The reference share price should be set to the
        // share price from the starting checkpoint, and the reference maturity
        // time should be set to the maturity time of the starting checkpoint.
        IHyperdrive.PoolInfo memory info0 = hyperdrive.getPoolInfo();
        assertEq(info0.negativeInterestReferenceSharePrice, sharePriceBefore);
        assertEq(
            info0.negativeInterestReferenceMaturityTime,
            checkpointTimeBefore + hyperdrive.getPoolConfig().positionDuration
        );

        // Another checkpoint passes with negative interest accruing. Ensure
        // that the reference share price stays the same. We initially record
        // negative interest in the starting checkpoint regardless of how much
        // time elapses. If the time delta was less than a checkpoint, the
        // reference maturity time won't change because we're still recording
        // negative interest in the starting checkpoint. If the time delta is
        // greater than or equal to a checkpoint, the reference maturity time
        // will be updated to the maturity time of the second checkpoint.
        advanceTime(
            checkpointDuration,
            -int256(hyperdrive.getPoolConfig().negativeInterestTolerance * 1000)
        );
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());
        IHyperdrive.PoolInfo memory info1 = hyperdrive.getPoolInfo();
        assertEq(
            info1.negativeInterestReferenceSharePrice,
            info0.negativeInterestReferenceSharePrice
        );
        if (_timeDelta < checkpointDuration) {
            assertEq(
                info1.negativeInterestReferenceMaturityTime,
                info0.negativeInterestReferenceMaturityTime
            );
        } else {
            assertEq(
                info1.negativeInterestReferenceMaturityTime,
                info0.negativeInterestReferenceMaturityTime + checkpointDuration
            );
        }
    }

    // Tests a scenario in which negative interest isn't recorded because
    // several checkpoints are minted. After a checkpoint is minted, negative
    // interest accrues. Later, the old checkpoints are minted which results
    // in the original negative interest being recorded.
    function test__negativeInterest__backfillingGapsWithNegativeInterest(
        uint256 _timeDelta
    ) external {
        // Alice deploys and initializes the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        deploy(alice, testConfig(fixedRate));
        initialize(alice, fixedRate, contribution);

        // Sample a time delta that is greater than two checkpoints.
        IHyperdrive.PoolConfig memory config = hyperdrive.getPoolConfig();
        uint256 checkpointDuration = config.checkpointDuration;
        uint256 positionDuration = config.positionDuration;
        _timeDelta = _timeDelta.normalizeToRange(
            checkpointDuration.mulDown(2e18),
            positionDuration.mulDown(0.5e18)
        );

        // A small amount of negative interest accrues and a checkpoint is
        // minted. Since the intermediate checkpoint was skipped, the reference
        // share price and maturity time shouldn't have been recorded.
        uint256 originalSharePrice = hyperdrive.getPoolInfo().sharePrice;
        uint256 originalCheckpointTime = hyperdrive.latestCheckpoint();
        advanceTime(
            _timeDelta,
            -int256(hyperdrive.getPoolConfig().negativeInterestTolerance * 1000)
        );
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());
        IHyperdrive.PoolInfo memory info0 = hyperdrive.getPoolInfo();
        assertEq(info0.negativeInterestReferenceSharePrice, 0);
        assertEq(info0.negativeInterestReferenceMaturityTime, 0);

        // Another checkpoint passes and a small amount of negative interest
        // accrues. This negative interest should be recorded.
        uint256 sharePriceBefore = hyperdrive.getPoolInfo().sharePrice;
        uint256 checkpointTimeBefore = hyperdrive.latestCheckpoint();
        advanceTime(
            CHECKPOINT_DURATION,
            -int256(hyperdrive.getPoolConfig().negativeInterestTolerance * 1000)
        );
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());
        info0 = hyperdrive.getPoolInfo();
        assertEq(info0.negativeInterestReferenceSharePrice, sharePriceBefore);
        assertEq(
            info0.negativeInterestReferenceMaturityTime,
            checkpointTimeBefore + positionDuration
        );

        // We go back and mint a checkpoint immediately after the starting
        // checkpoint. It will look forward and set it's share price to the
        // share price of the first checkpoint that has been minted. Negative
        // interest will be recorded, and since the original share price is
        // higher than the reference share price, the reference will be updated.
        // The reference maturity time will remain unchanged because it is
        // greater than the maturity time of the newly minted checkpoint.
        hyperdrive.checkpoint(originalCheckpointTime + checkpointDuration);
        IHyperdrive.PoolInfo memory info1 = hyperdrive.getPoolInfo();
        assertEq(info1.negativeInterestReferenceSharePrice, originalSharePrice);
        assertEq(
            info1.negativeInterestReferenceMaturityTime,
            info0.negativeInterestReferenceMaturityTime
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

    // Tests a scenario in which negative interest accrues and two LPs remove
    // liquidity at different times. The first LP should receive less base than
    // the second. During this scenario, Bob opens two longs at different times
    // and closes them in between the LP withdrawals
    function _test__negativeInterest__twoLps__long__long() internal {
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

        // Bob opens a long position.
        (testCase.maturityTime1, testCase.tradeAmount1) = openLong(
            bob,
            hyperdrive.calculateMaxLong() / 2
        );

        // Most of the terms passes and negative interest accrues.
        advanceTime(
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

        // Alice's base proceeds should be less that or equal base to Celine's.
        assertLe(testCase.aliceBaseProceeds, testCase.celineBaseProceeds);
    }

    // Tests a scenario in which negative interest accrues and two LPs remove
    // liquidity at different times. The first LP should receive less base than
    // the second. During this scenario, Bob opens two shorts at different times
    // and closes them in between the LP withdrawals
    function _test__negativeInterest__twoLps__short__short() internal {
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
        advanceTime(
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

        // Alice's base proceeds should be less that or equal base to Celine's.
        assertLe(testCase.aliceBaseProceeds, testCase.celineBaseProceeds);
    }

    // TODO: This test currently fails on main with the hardcoded seed. Once
    // that issue is addressed, we should revisit this.
    function test__negativeInterest__earlyWithdrawalsGetLess(
        bytes32 __seed
    ) internal {
        // FIXME
        __seed = 0x17c40277bdcc700449daf4cfc143a45267dfae59698a606c80ce0ca0a4f772d8;

        // Set the seed.
        _seed = __seed;

        // Alice initialize the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, fixedRate, contribution);
        contribution -= 2 * hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine adds liquidity.
        uint256 celineLpShares = addLiquidity(celine, contribution);

        // Accrues positive interest for a period. This gives us an interesting
        // starting share price.
        advanceTime(hyperdrive.getPoolConfig().positionDuration, 1e18);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Execute a series of random open trades.
        uint256 maturityTime0 = hyperdrive.maturityTimeFromLatestCheckpoint();
        Trade[] memory trades0 = randomOpenTrades();
        for (uint256 i = 0; i < trades0.length; i++) {
            executeTrade(trades0[i]);
        }

        // Time passes and negative interest accrues.
        {
            uint256 timeDelta = uint256(seed()).normalizeToRange(
                CHECKPOINT_DURATION,
                POSITION_DURATION.mulDown(0.99e18)
            );
            int256 variableRate = int256(uint256(seed())).normalizeToRange(
                -0.5e18,
                -0.1e18
            );
            advanceTimeWithCheckpoints(timeDelta, variableRate);
        }

        // Execute a series of random open trades.
        uint256 maturityTime1 = hyperdrive.maturityTimeFromLatestCheckpoint();
        Trade[] memory trades1 = randomOpenTrades();
        for (uint256 i = 0; i < trades1.length; i++) {
            executeTrade(trades1[i]);
        }

        // Alice removes her liquidity.
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);

        // Close all of the positions in a random order.
        Trade[] memory closeTrades;
        {
            Trade[] memory closeTrades0 = randomCloseTrades(
                maturityTime0,
                hyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Long,
                        maturityTime0
                    ),
                    alice
                ),
                maturityTime0,
                hyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Short,
                        maturityTime0
                    ),
                    alice
                )
            );
            Trade[] memory closeTrades1 = randomCloseTrades(
                maturityTime1,
                hyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Long,
                        maturityTime1
                    ),
                    alice
                ),
                maturityTime1,
                hyperdrive.balanceOf(
                    AssetId.encodeAssetId(
                        AssetId.AssetIdPrefix.Short,
                        maturityTime1
                    ),
                    alice
                )
            );
            closeTrades = combineTrades(closeTrades0, closeTrades1);
        }
        for (uint256 i = 0; i < closeTrades.length; i++) {
            executeTrade(closeTrades[i]);
        }

        // Celine removes her liquidity.
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

        // FIXME: Explain the fudge factor.
        //
        // Ensure that Alice's base proceeds were less than or equal to Celine's.
        assertLe(aliceBaseProceeds.mulDown(0.99e18), celineBaseProceeds);
    }
}
