// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

import "forge-std/console2.sol";

contract SandwichTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;


   function test_sandwich_add_liquidity_with_shorts() external {
        
        // Initialize the market
        uint256 fixedRate = 0.05e18;
        //deploy(alice, fixedRate, 1e18, 0.10e18, 0.0005e18, 0.15e18);
        deploy(alice, fixedRate, 1e18, 0.0e18, 0.0e18, 0.0e18);
        uint256 contribution = 1_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Get the poolInfo before trades happen.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        console2.log("poolInfoBefore.shareReserves", poolInfoBefore.shareReserves.toString(18));
        console2.log("poolInfoBefore.bondReserves", poolInfoBefore.bondReserves.toString(18));
        console2.log("apr", hyperdrive.calculateAPRFromReserves().toString(18));


        // Sandwich add liquidity with short.
        uint256 shortAmountSandwich = hyperdrive.calculateMaxShort().mulDivDown(0.95e18, 1e18);
        (uint256 maturityTimeSandwich, uint256 baseAmountSandwich) = openShort(celine, shortAmountSandwich);

        // Get the poolInfo after closing the positions.
        IHyperdrive.PoolInfo memory poolInfoMiddle = hyperdrive.getPoolInfo();
        console2.log("\npoolInfoMiddle.shareReserves", poolInfoMiddle.shareReserves.toString(18));
        console2.log("poolInfoMiddle.bondReserves", poolInfoMiddle.bondReserves.toString(18));
        console2.log("apr", hyperdrive.calculateAPRFromReserves().toString(18));

        // Bob adds liquidity.
        uint256 bobLpShares = addLiquidity(bob, 100_000e18);

        // Close the sandwiching short.
        uint256 baseProceedsSandwich = closeShort(celine, maturityTimeSandwich, shortAmountSandwich);

        // Get the poolInfo after closing the positions.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();
        console2.log("\npoolInfoAfter.shareReserves", poolInfoAfter.shareReserves.toString(18));
        console2.log("poolInfoAfter.bondReserves", poolInfoAfter.bondReserves.toString(18));
        console2.log("apr", hyperdrive.calculateAPRFromReserves().toString(18));

        console2.log("sandwich profit", (int256(baseProceedsSandwich)-int256(baseAmountSandwich)).toString(18));

        // if they aren't the same, then the pool should be the one that wins
        assertGe(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);
    }

    function test_sandwich_matured_short_with_shorts() external {
        
        // Initialize the market
        uint256 fixedRate = 0.05e18;
        //deploy(alice, fixedRate, 1e18, 0.10e18, 0.0005e18, 0.15e18);
        deploy(alice, fixedRate, 1e18, 0.0e18, 0.0e18, 0.0e18);
        uint256 contribution = 1_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Get the poolInfo before trades happen.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        console2.log("poolInfoBefore.shareReserves", poolInfoBefore.shareReserves.toString(18));
        console2.log("poolInfoBefore.bondReserves", poolInfoBefore.bondReserves.toString(18));
        console2.log("apr", hyperdrive.calculateAPRFromReserves().toString(18));

        // Open a short position.
        uint256 shortAmount = 100_000e18;
        (uint256 maturityTime, uint256 baseAmount) = openShort(bob, shortAmount);

        // Full term passes and variable interest accrues at the fixed rate
        advanceTime(POSITION_DURATION - 1 days, int256(fixedRate));

        // Sandwich the matured short with another short.
        uint256 shortAmountSandwich = hyperdrive.calculateMaxShort().mulDivDown(0.95e18, 1e18);
        (uint256 maturityTimeSandwich, uint256 baseAmountSandwich) = openShort(celine, shortAmountSandwich);

        // Get the poolInfo after closing the positions.
        IHyperdrive.PoolInfo memory poolInfoMiddle = hyperdrive.getPoolInfo();
        console2.log("\npoolInfoMiddle.shareReserves", poolInfoMiddle.shareReserves.toString(18));
        console2.log("poolInfoMiddle.bondReserves", poolInfoMiddle.bondReserves.toString(18));
        console2.log("apr", hyperdrive.calculateAPRFromReserves().toString(18));

        advanceTime(1 days, int256(fixedRate));

        // Close the matured short.
        uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount);


        // Close the sandwiching short.
        uint256 baseProceedsSandwich = closeShort(celine, maturityTimeSandwich, shortAmountSandwich);

        // Get the poolInfo after closing the positions.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();
        console2.log("\npoolInfoAfter.shareReserves", poolInfoAfter.shareReserves.toString(18));
        console2.log("poolInfoAfter.bondReserves", poolInfoAfter.bondReserves.toString(18));
        console2.log("apr", hyperdrive.calculateAPRFromReserves().toString(18));

        console2.log("\nshort profit", (int256(baseProceeds) - int256(baseAmount)).toString(18));
        console2.log("sandwich profit", (int256(baseProceedsSandwich)-int256(baseAmountSandwich)).toString(18));

        // if they aren't the same, then the pool should be the one that wins
        assertGe(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);
    }

    function test_sandwich_maturing_shorts()
        external
    {
        uint256 apr = 0.05e18;

        uint256 contribution = 1_000_000e18;
        initialize(alice, apr, contribution);

        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        console2.log("share/bonds resereves before openShort %s / %s", poolInfo.shareReserves / 1e18, poolInfo.bondReserves / 1e18);

        // 0. Alice shorts some bonds.
        uint256 bondAmount = 1e18;//100_000e18;
        (uint256 maturityTime, uint256 baseAmount) = openShort(alice, bondAmount, true);
        console2.log("maturing bonds", bondAmount / 1e18);

        // 1. let shorts mature
        // we move to the checkpoint AFTER maturity so we can do openShort + checkpoint(maturity) + closeShort
        // in a single transaction, risk-free profit.
        // It's also possible to do openShort 1 second before maturity, and the rest at maturity.
        uint256 checkpointDuration = hyperdrive.getPoolConfig().checkpointDuration;
        advanceTime(maturityTime - block.timestamp + checkpointDuration, 0.05e18);

        // 2. attacker Bob opens max shorts, leaving the pool with 0 share reserves
        // there is another bug where the protocol reverts when applying the checkpoint in `checkpoint` -> `_updateLiquidity`
        // the toUint128 reverts for uint256(_marketState.bondReserves).mulDivDown(_marketState.shareReserves, shareReserves))
        // therefore, we reduce the max short amount a little bit s.t. the updated bond reserves don't overflow uint128
        uint256 bondAmountSandwich = hyperdrive.calculateMaxShort().mulDivDown(0.3e18, 1e18);
        (uint256 maturityTimeSandwich, uint256 baseAmountSandwich) = openShort(bob, bondAmountSandwich, true);
        console2.log("sandwich: opened %s bonds with %s base", bondAmountSandwich / 1e18, baseAmountSandwich / 1e18);

        poolInfo = hyperdrive.getPoolInfo();
        console2.log("share/bonds resereves after openShort %s / %s", poolInfo.shareReserves / 1e18, poolInfo.bondReserves / 1e18);

        // 3. attacker triggers the maturing of old shorts, this adds back to the reserves
        hyperdrive.checkpoint(maturityTime);

        // 4. attacker now closes their shorts for a profit
        uint256 baseProceeds = closeShort(bob, maturityTimeSandwich, bondAmountSandwich);
        console2.log("sandwich: baseProceeds: %s, ROI: %s%", baseProceeds / 1e18, baseProceeds * 1e2 / baseAmountSandwich);

        poolInfo = hyperdrive.getPoolInfo();
        console2.log("share/bonds resereves at end %s / %s", poolInfo.shareReserves / 1e18, poolInfo.bondReserves / 1e18);
    }

    function test_sandwich_long_with_shorts(uint8 _apr, uint64 _timeDelta) external {
        uint256 apr = uint256(_apr) * 0.01e18;
        uint256 timeDelta = uint256(_timeDelta);
        vm.assume(apr >= 0.01e18 && apr <= 0.2e18);
        vm.assume(timeDelta <= FixedPointMath.ONE_18 && timeDelta >= 0);

        // Deploy the pool and initialize the market
        {
            uint256 timeStretchApr = 0.02e18;
            deploy(alice, timeStretchApr, 0, 0, 0);
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
            deploy(alice, timeStretchApr, 0, 0, 0);
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
            shortLoss = shortBasePaid.sub(shortBaseReturned);

            // long profit is the bonds received minus the base paid
            // bc we assume the bonds mature 1:1 to base
            uint256 longProfit = bondsReceived.sub(basePaid);
            sandwichProfit = longProfit.sub(shortLoss);
        }

        // Deploy the pool and initialize the market
        {
            uint256 timeStretchApr = 0.05e18;
            deploy(alice, timeStretchApr, 0, 0, 0);
        }
        initialize(alice, apr, contribution);

        // Calculate how much profit would be made from a simple long
        uint256 baselineProfit;
        {
            // open a long.
            uint256 basePaid = tradeSize;
            basePaid = basePaid.add(shortLoss);
            (uint256 longMaturityTime, uint256 bondsReceived) = openLong(
                celine,
                basePaid
            );
            closeLong(celine, longMaturityTime, bondsReceived);
            // profit is the bonds received minus the base paid
            // bc we assume the bonds mature 1:1 to base
            baselineProfit = bondsReceived.sub(basePaid);
        }
        assertGe(baselineProfit, sandwichProfit - 10000 gwei);
    }

    // TODO: Use the normalize function to improve this test.
    function test_sandwich_lp(uint8 _apr) external {
        uint256 apr = uint256(_apr) * 0.01e18;
        vm.assume(apr >= 0.01e18 && apr <= 0.2e18);

        // Deploy the pool with fees.
        {
            uint256 timeStretchApr = 0.02e18;
            uint256 curveFee = 0.001e18;
            deploy(alice, timeStretchApr, curveFee, 0, 0);
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
