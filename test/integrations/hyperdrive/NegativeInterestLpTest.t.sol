// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

// FIXME
import { console2 as console } from "forge-std/console2.sol";

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
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

    // FIXME
    function test__negativeInterest__largerMaturityTime() external {}

    // FIXME
    function test__negativeInterest__largerSharePrice() external {}

    // FIXME: Test accruing negative interest in several checkpoints. The max
    // share price and the maximum checkpoint ID should be used as the reference.
    // We'll need to test accruing negative interest in the past, and we should
    // test this in different scenarios.
    //
    // FIXME: Test accruing negative interest with gaps.

    // FIXME: Test opening random trades and then verifying that the first LP to
    // withdraw always gets less than the second LP.
}
