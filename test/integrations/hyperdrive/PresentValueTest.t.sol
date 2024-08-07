// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { console2 as console } from "forge-std/console2.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { MockHyperdrive } from "../../../contracts/test/MockHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract PresentValueTest is HyperdriveTest {
    using FixedPointMath for *;
    using HyperdriveUtils for *;
    using Lib for *;

    bytes32 internal _seed;

    // TODO: Remove this test. This is only used for documenting some cases that
    // deserve further investigation.
    //
    // TODO:
    // - [ ] Test different combinations of trades
    // - [ ] Test with add and remove liquidity (especially the short case)
    // - [ ] Test with fees
    //
    // TODO:
    // So far, this test illustrates that the present value is always being
    // overestimated, which is good from the perspective of add liquidity. The
    // only way to manipulate the present value so far is to close an old trade
    // and the difference is quite small. This needs to be investigated more
    // deeply to ensure that the protocol is secure and as fair as possible.
    //
    // TODO:
    // Large trades can result in the present value increasing or decreasing
    // after a trade is made. This shouldn't be a problem with fees, but fees
    // present a different challenge.
    function test_present_value_example() internal {
        uint256 lpShares = initialize(alice, 0.02e18, 500_000_000e18);

        console.log(
            "    presentValue: %s",
            HyperdriveUtils.presentValue(hyperdrive).toString(18)
        );

        // Time advances and value accrues.
        advanceTime(POSITION_DURATION, 0.2e18);

        console.log(
            "    presentValue: %s",
            HyperdriveUtils.presentValue(hyperdrive).toString(18)
        );

        // Open and close a short
        console.log("open and close a short - dt = 0");
        {
            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime, ) = openShort(alice, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );
        }

        // Open and close a long
        console.log("open and close a long - dt = 0");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 maturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the long position.
            closeLong(alice, maturityTime, longAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );
        }

        // Open a long and a short
        console.log("open and close a long and a short - dt = 0");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 shortMaturityTime, ) = openShort(alice, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the short position.
            closeShort(alice, shortMaturityTime, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );
        }

        // Open a long and close after some time
        console.log("open and close a long - dt = 0.5");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 maturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the long position.
            closeLong(alice, maturityTime, longAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );
        }

        // Open a long and close after some time
        console.log("open and close a short - dt = 0.5");
        {
            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime, ) = openShort(alice, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );
        }

        // Open a long and a short and close after some time
        console.log("open and close a long and short - dt = 0.5");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime, ) = openShort(alice, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );
        }

        // Open a long and a short and close after some time
        console.log("open and close a long and short - dt = 0.75");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Advance time.
            advanceTime(POSITION_DURATION / 4, 0.2e18);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime, ) = openShort(alice, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );
        }

        // Open a long and a short and close after some time. The close will be
        // broken up into several trades.
        console.log("open and close a long and short - dt = 0.5");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Advance time.
            advanceTime(POSITION_DURATION / 4, 0.2e18);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime, ) = openShort(alice, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount / 2);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount / 2);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount / 2);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount / 2 - 1e18);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );
            closeLong(alice, longMaturityTime, 1e18);
        }

        console.log("large trades - dt = 0.5");
        {
            // Open a long position.
            uint256 longPaid = 150_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Open a short position.
            uint256 shortAmount = 150_000_000e18;
            (uint256 maturityTime, ) = openShort(alice, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );
        }

        uint256 snapshotId = vm.snapshot();
        console.log("open short and LP removes liquidity");
        {
            // Open a short position.
            uint256 shortAmount = 150_000_000e18;
            (uint256 maturityTime, ) = openShort(alice, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // The LP removes liquidity.
            removeLiquidity(alice, lpShares);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Time passes and interest accrues.
            advanceTime(POSITION_DURATION, 0.2e18);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );
        }
        vm.revertTo(snapshotId);

        // TODO: Why does the present value go down when the long is closed?
        console.log("open short and long and LP removes liquidity");
        {
            // Open a short position.
            uint256 shortAmount = 150_000_000e18;
            (uint256 shortMaturityTime, ) = openShort(alice, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // The LP removes liquidity.
            removeLiquidity(alice, lpShares);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // TODO: This is one of the worst cases of the present value
            // decreasing.
            //
            // Close the long.
            closeLong(alice, longMaturityTime, longAmount).toString(18);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Time passes and interest accrues.
            advanceTime(POSITION_DURATION, 0.2e18);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );

            // Close the short position.
            closeShort(alice, shortMaturityTime, shortAmount);
            console.log(
                "    presentValue: %s",
                HyperdriveUtils.presentValue(hyperdrive).toString(18)
            );
        }
    }

    function test_present_value_instantaneous(bytes32 __seed) external {
        // Set the seed.
        _seed = __seed;

        // Initialize the pool.
        initialize(alice, 0.02e18, 500_000_000e18);

        // Get an initial present value.
        uint256 currentPresentValue = HyperdriveUtils.presentValue(hyperdrive);
        uint256 nextPresentValue;

        // Execute a series of random open trades. We ensure that the present
        // value stays the same.
        Trade[] memory trades = randomOpenTrades();
        for (uint256 i = 0; i < trades.length; i++) {
            executeTrade(trades[i]);
            nextPresentValue = HyperdriveUtils.presentValue(hyperdrive);
            assertGe(nextPresentValue, currentPresentValue);
            currentPresentValue = nextPresentValue;
        }

        // Execute a series of random close trades. We ensure that the present
        // value does not decrease.
        uint256 maturityTime = trades[trades.length - 1].maturityTime;
        trades = randomCloseTrades(
            maturityTime,
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                alice
            ),
            maturityTime,
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                alice
            )
        );
        for (uint256 i = 0; i < trades.length; i++) {
            executeTrade(trades[i]);
            nextPresentValue = HyperdriveUtils.presentValue(hyperdrive);
            assertGe(nextPresentValue, currentPresentValue);
            currentPresentValue = nextPresentValue;
        }
    }

    function test_present_value(bytes32 __seed) external {
        // TODO: It would be better to bound all of the intermediate present values
        // to the starting present value instead of bounding to the previous present
        // value.
        //
        // TODO: This tolerance is WAY too large.
        uint256 tolerance = 1_000_000e18;

        // Set the seed.
        _seed = __seed;

        // Initialize the pool.
        initialize(alice, 0.02e18, 500_000_000e18);

        // Execute a series of random open trades. We ensure that the present
        // value stays within a given tolerance.
        uint256 nextPresentValue;
        uint256 currentPresentValue = HyperdriveUtils.presentValue(hyperdrive);
        uint256 maturityTime0 = hyperdrive.maturityTimeFromLatestCheckpoint();
        Trade[] memory trades0 = randomOpenTrades();
        for (uint256 i = 0; i < trades0.length; i++) {
            executeTrade(trades0[i]);
            nextPresentValue = HyperdriveUtils.presentValue(hyperdrive);
            assertApproxEqAbs(nextPresentValue, currentPresentValue, tolerance);
            currentPresentValue = nextPresentValue;
        }

        // Time passes and interest accrues.
        {
            uint256 timeDelta = uint256(seed()).normalizeToRange(
                CHECKPOINT_DURATION,
                POSITION_DURATION.mulDown(0.99e18)
            );
            int256 variableRate = int256(uint256(seed())).normalizeToRange(
                -0.1e18,
                2e18
            );
            advanceTime(timeDelta, variableRate);
        }

        // Execute a series of random open trades. We ensure that the present
        // value stays within a given tolerance.
        currentPresentValue = HyperdriveUtils.presentValue(hyperdrive);
        uint256 maturityTime1 = hyperdrive.maturityTimeFromLatestCheckpoint();
        Trade[] memory trades1 = randomOpenTrades();
        for (uint256 i = 0; i < trades1.length; i++) {
            executeTrade(trades1[i]);
            nextPresentValue = HyperdriveUtils.presentValue(hyperdrive);
            assertApproxEqAbs(nextPresentValue, currentPresentValue, tolerance);
            currentPresentValue = nextPresentValue;
        }

        // Construct a set of close trades.
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

        // Execute a series of random close trades. We ensure that the present
        // value stays within a given tolerance.
        currentPresentValue = HyperdriveUtils.presentValue(hyperdrive);
        for (uint256 i = 0; i < closeTrades.length; i++) {
            executeTrade(closeTrades[i]);
            nextPresentValue = HyperdriveUtils.presentValue(hyperdrive);
            assertApproxEqAbs(nextPresentValue, currentPresentValue, tolerance);
            currentPresentValue = nextPresentValue;
        }
    }

    function test_path_independence(bytes32 __seed) external {
        // Set the seed.
        _seed = __seed;

        // Initialize the pool.
        initialize(alice, 0.02e18, 500_000_000e18);

        // Accrues positive interest for a period.
        advanceTime(hyperdrive.getPoolConfig().positionDuration, 1e18);

        // Execute a series of random open trades.
        uint256 maturityTime0 = hyperdrive.maturityTimeFromLatestCheckpoint();
        Trade[] memory trades0 = randomOpenTrades();
        for (uint256 i = 0; i < trades0.length; i++) {
            executeTrade(trades0[i]);
        }

        // Time passes and interest accrues.
        {
            uint256 timeDelta = uint256(seed()).normalizeToRange(
                CHECKPOINT_DURATION,
                POSITION_DURATION.mulDown(0.99e18)
            );
            int256 variableRate = int256(uint256(seed())).normalizeToRange(
                -0.5e18,
                1e18
            );
            advanceTime(timeDelta, variableRate);
        }

        // Execute a series of random open trades.
        uint256 maturityTime1 = hyperdrive.maturityTimeFromLatestCheckpoint();
        Trade[] memory trades1 = randomOpenTrades();
        for (uint256 i = 0; i < trades1.length; i++) {
            executeTrade(trades1[i]);
        }

        // Close all of the positions in a random order and record the ending
        // pool info.
        IHyperdrive.PoolInfo memory info0;
        Trade[] memory closeTrades;
        {
            uint256 snapshotId = vm.snapshot();

            // Construct a set of close trades.
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

            // Execute a series of random close trades. We ensure that the present
            // value stays within a given tolerance.
            for (uint256 i = 0; i < closeTrades.length; i++) {
                executeTrade(closeTrades[i]);
            }

            // Record the ending pool info.
            info0 = hyperdrive.getPoolInfo();

            vm.revertTo(snapshotId);
        }

        // Advance the seed a few times to ensure different trades in the next
        // round.
        for (uint256 i = 0; i < 5; i++) {
            seed();
        }

        // Close all of the positions in a different random order and record the
        // ending pool info.
        IHyperdrive.PoolInfo memory info1;
        {
            // Reorder the trades used in the last round and execute them.
            closeTrades = reorderTrades(closeTrades);
            for (uint256 i = 0; i < closeTrades.length; i++) {
                executeTrade(closeTrades[i]);
            }

            // Record the ending pool info.
            info1 = hyperdrive.getPoolInfo();
        }

        // Ensure that the ending YieldSpace coordinates are approximately
        // equal. The ending share reserves and share adjustment may not match
        // because the negative interest component of the share adjustment is
        // path dependent.
        assertApproxEqAbs(
            HyperdriveMath.calculateEffectiveShareReserves(
                info0.shareReserves,
                info0.shareAdjustment
            ),
            HyperdriveMath.calculateEffectiveShareReserves(
                info1.shareReserves,
                info1.shareAdjustment
            ),
            1e12
        );
        assertApproxEqAbs(info0.bondReserves, info1.bondReserves, 1e12);
    }

    function test_k_invariance(bytes32 __seed) external {
        uint256 tolerance = 1e12;

        // Set the seed.
        _seed = __seed;

        // Initialize the pool.
        initialize(alice, 0.02e18, 500_000_000e18);

        // Accrues positive interest for a period.
        advanceTime(hyperdrive.getPoolConfig().positionDuration, 1e18);

        // Execute a series of random open trades. We ensure that k remains
        // invariant throughout the trading.
        uint256 k = hyperdrive.k();
        uint256 maturityTime0 = hyperdrive.maturityTimeFromLatestCheckpoint();
        Trade[] memory trades0 = randomOpenTrades();
        for (uint256 i = 0; i < trades0.length; i++) {
            executeTrade(trades0[i]);
            assertApproxEqAbs(hyperdrive.k(), k, tolerance);
            k = hyperdrive.k();
        }

        // Time passes and interest accrues.
        {
            uint256 timeDelta = uint256(seed()).normalizeToRange(
                CHECKPOINT_DURATION,
                POSITION_DURATION.mulDown(0.99e18)
            );
            int256 variableRate = int256(uint256(seed())).normalizeToRange(
                -0.2e18,
                1e18
            );
            advanceTime(timeDelta, variableRate);
        }

        // Execute a series of random open trades. We ensure that k remains
        // invariant throughout the trading.
        k = hyperdrive.k();
        uint256 maturityTime1 = hyperdrive.maturityTimeFromLatestCheckpoint();
        Trade[] memory trades1 = randomOpenTrades();
        for (uint256 i = 0; i < trades1.length; i++) {
            executeTrade(trades1[i]);
            assertApproxEqAbs(hyperdrive.k(), k, tolerance);
            k = hyperdrive.k();
        }

        // Close all of the positions in a random order and verify that k is
        // invariant throughout the trading.
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
            assertApproxEqAbs(hyperdrive.k(), k, tolerance);
            k = hyperdrive.k();
        }
    }

    // TODO: It would be good to generalize this to more types of positions and
    // verify that the present value is monotonic when `_distributeExcessIdle`
    // is used to pay out withdrawal shares.
    //
    // This test verifies that the present value is monotonicly decreasing as
    // liquidity is removed from the reserves when the pool is net long.
    function test_present_value_monotonicity_long_trade(
        uint256 longBasePaid
    ) external {
        // Alice initializes the pool.
        initialize(alice, 0.02e18, 100_000_000e18);

        // Bob opens a long.
        longBasePaid = longBasePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong()
        );
        openLong(bob, longBasePaid);

        // Get the idle liquidity. This is the maximum amount that can be
        // removed from the reserves.
        uint256 idle = uint256(hyperdrive.solvency());

        uint256 lastValue;
        uint256 iterations = 10;
        for (uint256 i = 0; i < iterations; i++) {
            uint256 snapshotId = vm.snapshot();

            // Update the liquidity to simulate idle being removed from the reserves.
            int256 delta = -int256(
                1_000e18.mulDivDown(iterations - i, iterations) +
                    idle.mulDivDown(i, iterations)
            );
            MockHyperdrive(address(hyperdrive)).updateLiquidity(delta);

            // Ensure that the present value decreased.
            require(
                lastValue == 0 || hyperdrive.presentValue() < lastValue,
                "present value should decrease"
            );
            lastValue = hyperdrive.presentValue();

            vm.revertTo(snapshotId);
        }
    }

    /// Random Trading ///

    enum TradeType {
        Empty,
        OpenLong,
        OpenShort,
        CloseLong,
        CloseShort
    }

    struct Trade {
        TradeType tradeType;
        address trader;
        uint256 maturityTime;
        uint256 amount;
    }

    function executeTrade(Trade memory _trade) internal {
        if (_trade.tradeType == TradeType.OpenLong) {
            openLong(_trade.trader, _trade.amount);
        } else if (_trade.tradeType == TradeType.OpenShort) {
            openShort(_trade.trader, _trade.amount);
        } else if (_trade.tradeType == TradeType.CloseLong) {
            closeLong(_trade.trader, _trade.maturityTime, _trade.amount);
        } else if (_trade.tradeType == TradeType.CloseShort) {
            closeShort(_trade.trader, _trade.maturityTime, _trade.amount);
        }
    }

    function randomOpenTrades() internal returns (Trade[] memory) {
        Trade[] memory trades = new Trade[](10);

        for (uint256 i = 0; i < trades.length; i++) {
            trades[i] = Trade({
                tradeType: TradeType(uint256(seed()).normalizeToRange(1, 2)),
                trader: alice,
                maturityTime: 0,
                amount: uint256(seed()).normalizeToRange(1e18, 1_000_000e18)
            });
        }

        return trades;
    }

    function randomCloseTrades(
        uint256 longMaturityTime,
        uint256 longAmount,
        uint256 shortMaturityTime,
        uint256 shortAmount
    ) internal returns (Trade[] memory) {
        Trade[] memory trades = new Trade[](10);

        for (uint256 i = 0; i < trades.length; i++) {
            bool isLong = uint256(seed()) % 2 == 0;
            uint256 amount;
            if (isLong) {
                if (longAmount < 1e18) {
                    continue;
                }
                amount = uint256(seed()).normalizeToRange(1e18, longAmount);
                longAmount -= amount;
            } else {
                if (shortAmount < 1e18) {
                    continue;
                }
                amount = uint256(seed()).normalizeToRange(1e18, shortAmount);
                shortAmount -= amount;
            }
            trades[i] = Trade({
                tradeType: isLong ? TradeType.CloseLong : TradeType.CloseShort,
                trader: alice,
                maturityTime: isLong ? longMaturityTime : shortMaturityTime,
                amount: amount
            });
        }

        return trades;
    }

    function reorderTrades(
        Trade[] memory source
    ) internal returns (Trade[] memory result) {
        result = new Trade[](source.length);
        for (uint256 i = 0; i < result.length; i++) {
            // Sample a random index and copy from the source array to the new
            // array.
            uint256 sourceLength = source.length - i;
            uint256 idx = uint256(seed()).normalizeToRange(0, sourceLength - 1);
            result[i] = source[idx];

            // Move the last element of the source array to the sampled index.
            source[idx] = source[sourceLength - 1];
        }
    }

    function combineTrades(
        Trade[] memory a,
        Trade[] memory b
    ) internal returns (Trade[] memory result) {
        result = new Trade[](a.length + b.length);

        uint256 aIdx = 0;
        uint256 bIdx = 0;
        for (uint256 i = 0; i < result.length; i++) {
            if (aIdx >= a.length) {
                result[i] = b[bIdx++];
            } else if (bIdx >= b.length) {
                result[i] = a[aIdx++];
            } else if (uint256(seed()) % 2 == 0) {
                result[i] = a[aIdx++];
            } else {
                result[i] = b[bIdx++];
            }
        }
    }

    function seed() internal returns (bytes32 seed_) {
        seed_ = _seed;
        _seed = keccak256(abi.encodePacked(seed_));
        return seed_;
    }
}
