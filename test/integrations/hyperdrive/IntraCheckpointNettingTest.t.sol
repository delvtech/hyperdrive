// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { MockHyperdrive, IMockHyperdrive } from "../../mocks/MockHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

import "forge-std/console2.sol";

contract IntraCheckpointNettingTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function test_netting_fuzz(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) external {
        // Fuzz inputs Standard Range
        // initialSharePrice [0.5,5]
        // variableInterest [-50,50]
        // timeElapsed [0,365]
        // numTrades [1,10]
        // tradeSize [1,50_000_000/numTrades] 10% of the TVL
        initialSharePrice = initialSharePrice.normalizeToRange(0.5e18, 5e18);
        variableInterest = variableInterest.normalizeToRange(-.5e18, .5e18);
        timeElapsed = timeElapsed.normalizeToRange(0, POSITION_DURATION);
        numTrades = tradeSize.normalizeToRange(1, 10);
        tradeSize = tradeSize.normalizeToRange(1e18, 50_000_000e18 / numTrades);
        uint256 snapshotId = vm.snapshot();
        open_close_long(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_long_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_long_short_different_checkpoints(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        // Fuzz inputs Standard Range but limit to 1 trade
        initialSharePrice = initialSharePrice.normalizeToRange(0.5e18, 5e18);
        variableInterest = variableInterest.normalizeToRange(-.5e18, .5e18);
        timeElapsed = timeElapsed.normalizeToRange(0, POSITION_DURATION);
        numTrades = tradeSize.normalizeToRange(1, 1);
        tradeSize = tradeSize.normalizeToRange(1e18, 50_000_000e18 / numTrades);
        snapshotId = vm.snapshot();
        open_close_long(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_long_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_long_short_different_checkpoints(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        // Fuzz inputs Standard Range, but limit to negative variable interest
        initialSharePrice = initialSharePrice.normalizeToRange(0.5e18, 5e18);
        variableInterest = variableInterest.normalizeToRange(-.5e18, 0);
        timeElapsed = timeElapsed.normalizeToRange(0, POSITION_DURATION);
        numTrades = tradeSize.normalizeToRange(1, 10);
        tradeSize = tradeSize.normalizeToRange(1e18, 50_000_000e18 / numTrades);
        snapshotId = vm.snapshot();
        open_close_long(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_long_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_long_short_different_checkpoints(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        // Fuzz inputs Standard Range, but limit to negative variable interest with a trade szie of 1
        initialSharePrice = initialSharePrice.normalizeToRange(0.5e18, 5e18);
        variableInterest = variableInterest.normalizeToRange(-.5e18, 0);
        timeElapsed = timeElapsed.normalizeToRange(0, POSITION_DURATION);
        numTrades = tradeSize.normalizeToRange(1, 1);
        tradeSize = tradeSize.normalizeToRange(1e18, 50_000_000e18 / numTrades);
        snapshotId = vm.snapshot();
        open_close_long(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_long_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_long_short_different_checkpoints(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        // Fuzz inputs Standard Range, but limit to positive variable interest
        initialSharePrice = initialSharePrice.normalizeToRange(0.5e18, 5e18);
        variableInterest = variableInterest.normalizeToRange(0, 0.5e18);
        timeElapsed = timeElapsed.normalizeToRange(0, POSITION_DURATION);
        numTrades = tradeSize.normalizeToRange(1, 10);
        tradeSize = tradeSize.normalizeToRange(1e18, 50_000_000e18 / numTrades);
        snapshotId = vm.snapshot();
        open_close_long(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_long_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_long_short_different_checkpoints(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        // Fuzz inputs Standard Range, but limit to positive variable interest with a trade size of 1
        initialSharePrice = initialSharePrice.normalizeToRange(0.5e18, 5e18);
        variableInterest = variableInterest.normalizeToRange(0, 0.5e18);
        timeElapsed = timeElapsed.normalizeToRange(0, POSITION_DURATION);
        numTrades = tradeSize.normalizeToRange(1, 1);
        tradeSize = tradeSize.normalizeToRange(1e18, 50_000_000e18 / numTrades);
        snapshotId = vm.snapshot();
        open_close_long(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_long_short(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
        open_close_long_short_different_checkpoints(
            initialSharePrice,
            variableInterest,
            timeElapsed,
            tradeSize,
            numTrades
        );
        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();
    }

    function test_netting_open_close_long() external {
        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long is opened and immediately closed
        // - trade size is 1 million
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = 0 days;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long is opened and closed after 182.5 days
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION / 2;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long is opened and closed after POSITION_DURATION
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);
    }

    function open_close_long(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        // open a long
        uint256 maturityTimeLong = 0;
        uint256[] memory bondAmounts = new uint256[](numTrades);
        for (uint256 i = 0; i < numTrades; i++) {
            uint256 basePaidLong = tradeSize;
            uint256 bondAmount = 0;
            (maturityTimeLong, bondAmount) = openLong(bob, basePaidLong);
            bondAmounts[i] = bondAmount;
        }

        // fast forward time and accrue interest
        advanceTime(timeElapsed, variableInterest);

        // close the long.
        for (uint256 i = 0; i < numTrades; i++) {
            closeLong(bob, maturityTimeLong, bondAmounts[i]);
        }

        // exposure should be 0
        int256 exposure = MockHyperdrive(address(hyperdrive))
            .getCurrentExposure();
        assertLe(exposure, 0);
        assertApproxEqAbs(exposure, 0, 1e18);
    }

    function test_netting_open_close_short() external {
        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a short is opened and immediately closed
        // - trade size is 1 million
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = 0;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a short is opened and closed after 182.5 days
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION / 2;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a short is opened and closed after 365 days
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);
    }

    function open_close_short(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        // open a short
        uint256 shortAmount = tradeSize;
        uint256 maturityTimeShort = 0;
        for (uint256 i = 0; i < numTrades; i++) {
            (maturityTimeShort, ) = openShort(bob, shortAmount);
        }

        // fast forward time and accrue interest
        advanceTime(timeElapsed, variableInterest);

        // close the short
        for (uint256 i = 0; i < numTrades; i++) {
            closeShort(bob, maturityTimeShort, shortAmount);
        }

        // exposure should be 0
        int256 exposure = MockHyperdrive(address(hyperdrive))
            .getCurrentExposure();
        assertLe(exposure, 0);
        assertApproxEqAbs(exposure, 0, 1e5);
    }

    function test_netting_open_close_long_short() external {
        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long and short is opened and immediately closed
        // - trade size is 1 million
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = 0;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long and short is opened and closed after 182.5 days
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION / 2;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long and short is opened and closed after 365 days
        // - trade size is 1 million
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            uint256 tradeSize = 1_000_000e18;
            uint256 numTrades = 1;
            open_close_long_short(
                initialSharePrice,
                variableInterest,
                timeElapsed,
                tradeSize,
                numTrades
            );
        }
        vm.revertTo(snapshotId);
    }

    function open_close_long_short(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) internal {
        // initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        // open a long position.
        uint256 maturityTimeLong = 0;
        uint256[] memory bondAmounts = new uint256[](numTrades);
        for (uint256 i = 0; i < numTrades; i++) {
            uint256 basePaidLong = tradeSize;
            uint256 bondAmount = 0;
            (maturityTimeLong, bondAmount) = openLong(bob, basePaidLong);
            bondAmounts[i] = bondAmount;
        }

        // open a short position.
        uint256 shortAmount = tradeSize;
        uint256 maturityTimeShort = 0;
        for (uint256 i = 0; i < numTrades; i++) {
            (maturityTimeShort, ) = openShort(bob, shortAmount);
        }

        // fast forward time and accrue interest
        advanceTime(timeElapsed, variableInterest);

        // close the long.
        for (uint256 i = 0; i < numTrades; i++) {
            closeLong(bob, maturityTimeLong, bondAmounts[i]);
            closeShort(bob, maturityTimeShort, shortAmount);
        }

        // exposure should be 0
        int256 exposure = MockHyperdrive(address(hyperdrive))
            .getCurrentExposure();
        assertLe(exposure, 0);
        assertApproxEqAbs(exposure, 0, 1e12);
    }

    function open_close_long_short_different_checkpoints(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 timeElapsed,
        uint256 tradeSize,
        uint256 numTrades
    ) internal {
        // initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        // open positions
        uint256[] memory longMaturityTimes = new uint256[](numTrades);
        uint256[] memory shortMaturityTimes = new uint256[](numTrades);
        uint256[] memory bondAmounts = new uint256[](numTrades);
        uint256 shortAmount = tradeSize;
        for (uint256 i = 0; i < numTrades; i++) {
            uint256 basePaidLong = tradeSize;
            (uint256 maturityTimeLong, uint256 bondAmount) = openLong(
                bob,
                basePaidLong
            );
            longMaturityTimes[i] = maturityTimeLong;
            bondAmounts[i] = bondAmount;

            // fast forward time and accrue interest
            advanceTime(timeElapsed, variableInterest);
            (uint256 maturityTimeShort, ) = openShort(bob, shortAmount);
            shortMaturityTimes[i] = maturityTimeShort;
        }

        // close the positions
        for (uint256 i = 0; i < numTrades; i++) {
            closeLong(bob, longMaturityTimes[i], bondAmounts[i]);
            // fast forward time and accrue interest
            advanceTime(timeElapsed, variableInterest);

            closeShort(bob, shortMaturityTimes[i], shortAmount);
        }

        // exposure should be 0
        int256 exposure = MockHyperdrive(address(hyperdrive))
            .getCurrentExposure();
        assertLe(exposure, 0);
        assertApproxEqAbs(exposure, 0, 1e12);
    }
}
