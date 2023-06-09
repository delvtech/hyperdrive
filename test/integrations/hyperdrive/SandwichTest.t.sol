// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";
import "forge-std/console2.sol";

contract SandwichTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function test_sandwich_trades(uint8 _apr, uint64 _timeDelta) external {
        uint256 apr = uint256(_apr) * 0.01e18;
        uint256 timeDelta = uint256(_timeDelta);
        vm.assume(apr >= 0.01e18 && apr <= 0.2e18);
        vm.assume(timeDelta <= FixedPointMath.ONE_18 && timeDelta >= 0);

        // Deploy the pool with fees.
        {
            uint256 timeStretchApr = 0.02e18;
            deploy(alice, timeStretchApr, 0, 0, 0);
        }

        // Initialize the market.
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

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
        (uint256 shortMaturitytime, ) = openShort(celine, shortAmount);

        // Bob closes his long.
        closeLong(bob, longMaturityTime, longAmount);

        // Celine immediately closes her short.
        closeShort(celine, shortMaturitytime, shortAmount);

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

    function test_sandwich_long_trade(
        uint256 apr,
        uint256 tradeSize
    ) external {

        // limit the fuzz testing to variableRate's less than or equal to 50%
        apr = apr.normalizeToRange(.01e18, .5e18);

        // ensure a feasible trade size
        tradeSize = tradeSize.normalizeToRange(
            1_000e18,
            50_000_000e18 - 1e18
        );
        console2.log("apr: ", apr.toString(18));
        console2.log("tradeSize: ", tradeSize.toString(18));
        // Deploy the pool with fees.
        {
            uint256 timeStretchApr = 0.05e18;
            deploy(alice, timeStretchApr, 0, 0, 0);
        }

        // Initialize the market.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);
        uint256 bobLoss;
        // Calculate how much profit would be made from a long sandwiched by shorts
        uint256 sandwichProfit;
        {
            IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
            console2.log("\nSANDWICH TRADE");
            console2.log("\ninitial state");
            console2.log("shareReserves: ", poolInfo.shareReserves.toString(18));
            console2.log("bondReserves: ", poolInfo.bondReserves.toString(18));
            console2.log("APR:", HyperdriveUtils.calculateAPRFromReserves(hyperdrive).toString(18));

            // Bob opens a short.
            uint256 bondsShorted = tradeSize;//10_000_000e18;
            (uint256 shortMaturitytime, uint256 bobStartAmount) = openShort(bob, bondsShorted);

            poolInfo = hyperdrive.getPoolInfo();
            console2.log("\nafter open short");
            console2.log("bonds shorted: ", bondsShorted.toString(18)," for: ", bobStartAmount.toString(18));
            console2.log("shareReserves: ", poolInfo.shareReserves.toString(18));
            console2.log("bondReserves: ", poolInfo.bondReserves.toString(18));
            console2.log("APR:", HyperdriveUtils.calculateAPRFromReserves(hyperdrive).toString(18));

            // Celine opens a long.
            uint256 basePaid = tradeSize;//10_000_000e18;
            (uint256 longMaturityTime, uint256 bondsReceived) = openLong(
                celine,
                basePaid
            );
            poolInfo = hyperdrive.getPoolInfo();
            console2.log("\nafter open long");
            console2.log("bonds received: ", bondsReceived.toString(18));
            console2.log("shareReserves: ", poolInfo.shareReserves.toString(18));
            console2.log("bondReserves: ", poolInfo.bondReserves.toString(18));
            console2.log("APR:", HyperdriveUtils.calculateAPRFromReserves(hyperdrive).toString(18));

            // Bob immediately closes short.
            uint256 bobEndAmount = closeShort(bob, shortMaturitytime, bondsShorted);
            poolInfo = hyperdrive.getPoolInfo();
            console2.log("\nafter close short");
            console2.log("base returned: ", bobEndAmount.toString(18));
            console2.log("shareReserves: ", poolInfo.shareReserves.toString(18));
            console2.log("bondReserves: ", poolInfo.bondReserves.toString(18));
            console2.log("APR:", HyperdriveUtils.calculateAPRFromReserves(hyperdrive).toString(18));

            // console2.log("\nbob start amount: ", bobStartAmount.toString(18));
            // console2.log("bob end amount: ", bobEndAmount.toString(18));
            bobLoss = bobStartAmount.sub(bobEndAmount);
            // console2.log("bob loss: ", bobLoss.toString(18));

            // Some of the term passes and interest accrues at the starting APR.
            //advanceTime(POSITION_DURATION, int256(apr));

            // Celine closes long.
            closeLong(celine, longMaturityTime, bondsReceived);
            poolInfo = hyperdrive.getPoolInfo();
            console2.log("\nafter close long");
            console2.log("base received: ", bondsReceived.toString(18));
            console2.log("shareReserves: ", poolInfo.shareReserves.toString(18));
            console2.log("bondReserves: ", poolInfo.bondReserves.toString(18));
            console2.log("APR:", HyperdriveUtils.calculateAPRFromReserves(hyperdrive).toString(18));
            // console2.log("celine start amount: ", basePaid.toString(18));
            // console2.log("celine end amount: ", celineEndAmount.toString(18));
            uint256 celineProfit = bondsReceived.sub(basePaid);
            // console2.log("celine profit: ", celineProfit.toString(18));

            sandwichProfit = celineProfit.sub(bobLoss);
        }


        // Deploy the pool with fees.
        {
            uint256 timeStretchApr = 0.05e18;
            deploy(alice, timeStretchApr, 0, 0, 0);
        }

        initialize(alice, apr, contribution);

        // Calculate how much proft would be made from a simple long
        uint256 baselineProfit;
        {
            console2.log("\nNORMAL TRADE");
            IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
            console2.log("\ninitial state");
            console2.log("shareReserves: ", poolInfo.shareReserves.toString(18));
            console2.log("bondReserves: ", poolInfo.bondReserves.toString(18));
            console2.log("APR:", HyperdriveUtils.calculateAPRFromReserves(hyperdrive).toString(18));
            // Celine opens a long.
            uint256 basePaid = tradeSize;
            basePaid = basePaid.add(bobLoss);
            (uint256 longMaturityTime, uint256 bondsReceived) = openLong(
                celine,
                basePaid
            );
            poolInfo = hyperdrive.getPoolInfo();
            console2.log("\nafter open long");
            console2.log("bonds received: ", bondsReceived.toString(18));
            console2.log("shareReserves: ", poolInfo.shareReserves.toString(18));
            console2.log("bondReserves: ", poolInfo.bondReserves.toString(18));
            console2.log("APR:", HyperdriveUtils.calculateAPRFromReserves(hyperdrive).toString(18));
            closeLong(celine, longMaturityTime, bondsReceived);
            baselineProfit = bondsReceived.sub(basePaid);
            console2.log("\nafter close long");
            console2.log("shareReserves: ", poolInfo.shareReserves.toString(18));
            console2.log("bondReserves: ", poolInfo.bondReserves.toString(18));
            console2.log("APR:", HyperdriveUtils.calculateAPRFromReserves(hyperdrive).toString(18));

        }

        console2.log("\nProfit");
        console2.log("baseline profit: ", baselineProfit.toString(18));
        console2.log("sandwich profit: ", sandwichProfit.toString(18));

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
