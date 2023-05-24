// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import { Lib } from "test/utils/Lib.sol";

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive, HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";

contract PresentValueTest is HyperdriveTest {
    using Lib for *;
    using FixedPointMath for *;

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

        console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

        // Time advances and value accrues.
        advanceTime(POSITION_DURATION, 0.2e18);

        console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

        // Open and close a short
        console.log("open and close a short - dt = 0");
        {
            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime,) = openShort(alice, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));
        }

        // Open and close a long
        console.log("open and close a long - dt = 0");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 maturityTime, uint256 longAmount) = openLong(alice, longPaid);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the long position.
            closeLong(alice, maturityTime, longAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));
        }

        // Open a long and a short
        console.log("open and close a long and a short - dt = 0");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(alice, longPaid);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 shortMaturityTime,) = openShort(alice, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the short position.
            closeShort(alice, shortMaturityTime, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));
        }

        // Open a long and close after some time
        console.log("open and close a long - dt = 0.5");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 maturityTime, uint256 longAmount) = openLong(alice, longPaid);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the long position.
            closeLong(alice, maturityTime, longAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));
        }

        // Open a long and close after some time
        console.log("open and close a short - dt = 0.5");
        {
            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime,) = openShort(alice, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));
        }

        // Open a long and a short and close after some time
        console.log("open and close a long and short - dt = 0.5");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(alice, longPaid);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime,) = openShort(alice, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));
        }

        // Open a long and a short and close after some time
        console.log("open and close a long and short - dt = 0.75");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(alice, longPaid);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 4, 0.2e18);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime,) = openShort(alice, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));
        }

        // Open a long and a short and close after some time. The close will be
        // broken up into several trades.
        console.log("open and close a long and short - dt = 0.5");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(alice, longPaid);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 4, 0.2e18);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime,) = openShort(alice, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount / 2);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount / 2);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount / 2);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount / 2 - 1e18);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));
            closeLong(alice, longMaturityTime, 1e18);
        }

        console.log("large trades - dt = 0.5");
        {
            // Open a long position.
            uint256 longPaid = 150_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(alice, longPaid);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Open a short position.
            uint256 shortAmount = 150_000_000e18;
            (uint256 maturityTime,) = openShort(alice, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));
        }

        uint256 snapshotId = vm.snapshot();
        console.log("open short and LP removes liquidity");
        {
            // Open a short position.
            uint256 shortAmount = 150_000_000e18;
            (uint256 maturityTime,) = openShort(alice, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // The LP removes liquidity.
            removeLiquidity(alice, lpShares);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Time passes and interest accrues.
            advanceTime(POSITION_DURATION, 0.2e18);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));
        }
        vm.revertTo(snapshotId);

        // TODO: Why does the present value go down when the long is closed?
        console.log("open short and long and LP removes liquidity");
        {
            // Open a short position.
            uint256 shortAmount = 150_000_000e18;
            (uint256 shortMaturityTime,) = openShort(alice, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(alice, longPaid);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // The LP removes liquidity.
            removeLiquidity(alice, lpShares);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // TODO: This is one of the worst cases of the present value
            // decreasing.
            //
            // Close the long.
            closeLong(alice, longMaturityTime, longAmount).toString(18);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Time passes and interest accrues.
            advanceTime(POSITION_DURATION, 0.2e18);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));

            // Close the short position.
            closeShort(alice, shortMaturityTime, shortAmount);
            console.log("    presentValue: %s", HyperdriveUtils.presentValue(hyperdrive).toString(18));
        }
    }

    function test_present_value_instantaneous(bytes32 __seed) external {
        // Set the seed.
        _seed = __seed;

        // Initialiaze the pool.
        initialize(alice, 0.02e18, 500_000_000e18);

        // Get an initial present value.
        uint256 currentPresentValue = HyperdriveUtils.presentValue(hyperdrive);
        uint256 nextPresentValue;

        // Execute a series of random open trades. We ensure that the present
        // value does not decrease.
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
            hyperdrive.balanceOf(AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime), alice),
            maturityTime,
            hyperdrive.balanceOf(AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime), alice)
        );
        for (uint256 i = 0; i < trades.length; i++) {
            executeTrade(trades[i]);
            nextPresentValue = HyperdriveUtils.presentValue(hyperdrive);
            assertGe(nextPresentValue, currentPresentValue);
            currentPresentValue = nextPresentValue;
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

    function seed() internal returns (bytes32 seed_) {
        seed_ = _seed;
        _seed = keccak256(abi.encodePacked(seed_));
        return seed_;
    }
}
