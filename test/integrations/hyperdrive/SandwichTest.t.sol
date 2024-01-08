// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract SandwichTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function test_sandwich_trades(uint8 _apr, uint64 _timeDelta) external {
        uint256 apr = uint256(_apr) * 0.01e18;
        uint256 timeDelta = uint256(_timeDelta);
        vm.assume(apr >= 0.01e18 && apr <= 0.2e18);
        vm.assume(timeDelta <= ONE && timeDelta >= 0);

        // Deploy the pool and initialize the market
        {
            uint256 timeStretchApr = 0.02e18;
            deploy(alice, timeStretchApr, 0, 0, 0, 0);
        }
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);
        contribution -= 2 * hyperdrive.getPoolConfig().minimumShareReserves;

        // Bob opens a long.
        uint256 longPaid = 50_000_000e18;
        (uint256 longMaturityTime, uint256 longAmount) = openLong(
            bob,
            longPaid
        );

        // Some of the term passes and interest accrues at the starting APR.
        uint256 timeAdvanced = POSITION_DURATION.mulDown(timeDelta);
        advanceTime(timeAdvanced, int256(apr));

        // Celine opens a short.
        uint256 shortAmount = 200_000_000e18;
        (uint256 shortMaturityTime, ) = openShort(celine, shortAmount);

        // Bob closes his long.
        closeLong(bob, longMaturityTime, longAmount);

        // Celine immediately closes her short.
        closeShort(celine, shortMaturityTime, shortAmount);

        // Ensure the proceeds from the sandwich attack didn't negatively
        // impact the LP. With this in mind, they should have made at least as
        // much money as if no trades had been made and they just collected
        // variable APR.
        (uint256 lpProceeds, ) = removeLiquidity(alice, lpShares);

        // Calculate how much interest has accrued on the initial contribution
        (uint256 contributionPlusInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(contribution, int256(apr), timeAdvanced);
        assertGe(lpProceeds, contributionPlusInterest);
    }

    function test_sandwich_long_trade(uint256 apr, uint256 tradeSize) external {
        // limit the fuzz testing to variableRate's less than or equal to 50%
        apr = apr.normalizeToRange(.01e18, .5e18);

        // ensure a feasible trade size
        tradeSize = tradeSize.normalizeToRange(1_000e18, 50_000_000e18 - 1e18);

        // Deploy the pool and initialize the market
        {
            uint256 timeStretchApr = 0.05e18;
            deploy(alice, timeStretchApr, 0, 0, 0, 0);
        }
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        uint256 shortLoss;
        // Calculate how much profit would be made from a long sandwiched by shorts
        uint256 sandwichProfit;
        {
            // open a short.
            uint256 bondsShorted = tradeSize; //10_000_000e18;
            (uint256 shortMaturityTime, uint256 shortBasePaid) = openShort(
                bob,
                bondsShorted
            );

            // open a long.
            uint256 basePaid = tradeSize; //10_000_000e18;
            (, uint256 bondsReceived) = openLong(bob, basePaid);

            // immediately close short.
            uint256 shortBaseReturned = closeShort(
                bob,
                shortMaturityTime,
                bondsShorted
            );
            shortLoss = shortBasePaid - shortBaseReturned;

            // long profit is the bonds received minus the base paid
            // bc we assume the bonds mature 1:1 to base
            uint256 longProfit = bondsReceived - basePaid;
            sandwichProfit = longProfit - shortLoss;
        }

        // Deploy the pool and initialize the market
        {
            uint256 timeStretchApr = 0.05e18;
            deploy(alice, timeStretchApr, 0, 0, 0, 0);
        }
        initialize(alice, apr, contribution);

        // Calculate how much profit would be made from a simple long
        uint256 baselineProfit;
        {
            // open a long.
            uint256 basePaid = tradeSize;
            basePaid = basePaid + shortLoss;
            (uint256 longMaturityTime, uint256 bondsReceived) = openLong(
                celine,
                basePaid
            );
            closeLong(celine, longMaturityTime, bondsReceived);
            // profit is the bonds received minus the base paid
            // bc we assume the bonds mature 1:1 to base
            baselineProfit = bondsReceived - basePaid;
        }
        assertGe(baselineProfit, sandwichProfit - 10000 gwei);
    }

    function test_sandwich_short_trade(
        uint256 fixedRate,
        uint256 contribution,
        uint256 tradeAmount,
        uint256 sandwichAmount
    ) external {
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        deploy(alice, config);
        fixedRate = fixedRate.normalizeToRange(0.001e18, 1e18);
        contribution = contribution.normalizeToRange(1_000e18, 500_000_000e18);
        uint256 lpShares = initialize(alice, fixedRate, contribution);
        contribution -= 2 * config.minimumShareReserves;

        // Bob opens a short.
        tradeAmount = tradeAmount.normalizeToRange(
            1e18,
            hyperdrive.calculateMaxShort().mulDown(0.9e18)
        );
        openShort(bob, tradeAmount);

        // Most of the term passes and no interest accrues.
        advanceTime(POSITION_DURATION - 12 seconds, 0);

        // Celine opens a short to sandwich the closing of Bob's short.
        sandwichAmount = sandwichAmount.normalizeToRange(
            1e18,
            hyperdrive.calculateMaxShort()
        );
        (uint256 maturityTime, uint256 shortPayment) = openShort(
            celine,
            sandwichAmount
        );

        // The rest of the term passes and no interest accrues.
        advanceTime(12 seconds, 0);

        // Celine closes her short. Her short should have been unprofitable.
        uint256 shortProceeds = closeShort(
            celine,
            maturityTime,
            sandwichAmount
        );
        assertLt(shortProceeds, shortPayment);

        // Alice removes her liquidity. She should receive at least as much as
        // as she put in.
        (uint256 withdrawalProceeds, ) = removeLiquidity(alice, lpShares);
        assertGe(withdrawalProceeds, contribution);
    }

    // TODO: Use the normalize function to improve this test.
    function test_sandwich_lp(uint8 _apr) external {
        uint256 apr = uint256(_apr) * 0.01e18;
        vm.assume(apr >= 0.01e18 && apr <= 0.2e18);

        // Deploy the pool with fees.
        {
            uint256 timeStretchApr = 0.02e18;
            uint256 curveFee = 0.001e18;
            deploy(alice, timeStretchApr, curveFee, 0, 0, 0);
        }

        // Initialize the market.
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, apr, contribution);

        // Bob opens a large long and a short.
        uint256 tradeAmount = 100_000_000e18;
        (uint256 longMaturityTime, uint256 longAmount) = openLong(
            bob,
            tradeAmount
        );
        (uint256 shortMaturityTime, ) = openShort(bob, tradeAmount);

        // Bob adds liquidity. Bob shouldn't receive more LP shares than Alice.
        uint256 bobLpShares = addLiquidity(bob, contribution);
        assertLe(bobLpShares, aliceLpShares);

        // Bob closes his positions.
        closeLong(bob, longMaturityTime, longAmount);
        closeShort(bob, shortMaturityTime, tradeAmount);

        // Bob removes his liquidity.
        removeLiquidity(bob, bobLpShares);

        // Ensure the proceeds from the sandwich attack didn't negatively impact
        // the LP.
        (uint256 lpProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertGe(lpProceeds, contribution);
    }
}
