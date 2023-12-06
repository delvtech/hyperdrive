// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

import "forge-std/console2.sol";

contract LPFairnessTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using HyperdriveUtils for *;
    using Lib for *;

    function test_zombie_interest_long_lp(
        uint256 variableRateParam,
        uint256 longTradeSizeParam,
        uint256 zombieTimeParam
    ) external {
        // Initialize the pool with capital.
        deploy(bob, 0.035e18, 1e18, 0, 0, 0);
        initialize(bob, 0.035e18, 2 * MINIMUM_SHARE_RESERVES);

        // Alice adds liquidity.
        uint256 initialLiquidity = 500_000_000e18;
        uint256 aliceLpShares = addLiquidity(alice, 500_000_000e18);

        // Limit the fuzz testing to variableRate's less than or equal to 200%
        int256 variableRate = int256(
            variableRateParam.normalizeToRange(0, 2e18)
        );
        console2.log("variableRate", variableRate.toString(18));

        // Ensure a feasible trade size.
        uint256 longTradeSize = longTradeSizeParam.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong() - MINIMUM_TRANSACTION_AMOUNT
        );
        console2.log("longTradeSize", longTradeSize.toString(18));

        // A random amount of time passes to pass after the term before the position is redeemed.
        uint256 zombieTime = zombieTimeParam.normalizeToRange(
            1,
            POSITION_DURATION
        );
        console2.log("zombieTime", zombieTime.toString(18));

        // Celine opens a long.
        (uint256 maturityTime, uint256 bondsReceived) = openLong(
            celine,
            longTradeSize
        );

        // Time passes with interest.
        advanceTimeWithCheckpoints2(
            POSITION_DURATION + zombieTime,
            variableRate
        );
        console2.log("after advanceTimeWithCheckpoints2");

        // Celina redeems her long late.
        uint256 longProceeds = closeLong(celine, maturityTime, bondsReceived);
        console2.log("after closeLong");

        // Alice removes liquidity.
        (uint256 withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        console2.log("withdrawalProceeds", withdrawalProceeds.toString(18));
        console2.log("after removeLiquidity");

        // Because withdrawalProceeds have longProceeds worth of zombie interest,
        // we calculate the actual interest rate and compare it to the expected rate.
        int256 actualRate = (int256(withdrawalProceeds) - int256(initialLiquidity))*1e18/int256(initialLiquidity);

        console2.log("actualRate", actualRate.toString(18));
        (uint256 expectedProceeds, ) = HyperdriveUtils
            .calculateCompoundInterest(
                initialLiquidity + longTradeSize,
                variableRate,
                POSITION_DURATION + zombieTime
            );
        int256 expectedRate = (int256(expectedProceeds) - int256(longProceeds) - int256(initialLiquidity))*1e18/int256(initialLiquidity);
        console2.log("expectedRate", expectedRate.toString(18));
        assertApproxEqAbs(actualRate, expectedRate, 1e12);
    }

    function test_zombie_interest_short_lp(
        uint256 variableRateParam,
        uint256 shortTradeSizeParam,
        uint256 zombieTimeParam
    ) external {
        // Initialize the pool with capital.
        deploy(bob, 0.035e18, 1e18, 0, 0, 0);
        initialize(bob, 0.035e18, 2 * MINIMUM_SHARE_RESERVES);

        // Alice adds liquidity.
        uint256 initialLiquidity = 500_000_000e18;
        uint256 aliceLpShares = addLiquidity(alice, 500_000_000e18);

        // limit the fuzz testing to variableRate's less than or equal to 25%
        int256 variableRate = int256(
            variableRateParam.normalizeToRange(0, 0.25e18)
        );

        console2.log("variableRate", variableRate.toString(18));

        // Ensure a feasible trade size.
        uint256 shortTradeSize = shortTradeSizeParam.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxShort() - MINIMUM_TRANSACTION_AMOUNT
        );
        console2.log("shortTradeSize", shortTradeSize.toString(18));

        // A random amount of time passes to pass after the term before the position is redeemed.
        uint256 zombieTime = zombieTimeParam.normalizeToRange(
            1,
            POSITION_DURATION
        );
        console2.log("zombieTime", zombieTime.toString(18));

        // Celine opens a short.
        (uint256 maturityTime, uint256 shortDeposit) = openShort(
            celine,
            shortTradeSize
        );

        // Time passes with interest.
        advanceTimeWithCheckpoints2(
            POSITION_DURATION + zombieTime,
            variableRate
        );
        console2.log("after advanceTimeWithCheckpoints2");

        // Celina redeems her short late.
        uint256 shortProceeds = closeShort(
            celine,
            maturityTime,
            shortTradeSize
        );
        console2.log("after closeShort");

        // Alice removes liquidity.
        (uint256 withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        console2.log("after removeLiquidity");

        // Because withdrawalProceeds have shortDeposit worth of zombie interest,
        // we calculate the actual interest rate and compare it to the expected rate.
        uint256 actualRate = (withdrawalProceeds - initialLiquidity).divDown(
            initialLiquidity
        );
        (uint256 expectedProceeds, ) = HyperdriveUtils
            .calculateCompoundInterest(
                initialLiquidity + shortDeposit,
                variableRate,
                POSITION_DURATION + zombieTime
            );
        expectedProceeds -= shortProceeds;
        uint256 expectedRate = (expectedProceeds - initialLiquidity).divDown(
            initialLiquidity
        );
        assertApproxEqAbs(actualRate, expectedRate, 1e18);
    }
}
