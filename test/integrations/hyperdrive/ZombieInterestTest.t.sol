// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "test/utils/HyperdriveTest.sol";
import { MockHyperdrive, IMockHyperdrive } from "contracts/test/MockHyperdrive.sol";
import { Lib } from "test/utils/Lib.sol";

contract ZombieInterestTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using HyperdriveUtils for *;
    using Lib for *;

    function test_zombie_interest_long_lp(
        uint256 variableRateParam,
        uint256 longTradeSizeParam,
        uint256 delayTimeFirstTradeParam,
        uint256 zombieTimeParam,
        bool removeLiquidityBeforeMaturityParam,
        bool closeLongFirstParam
    ) external {
        _test_zombie_interest_long_lp(
            variableRateParam,
            longTradeSizeParam,
            delayTimeFirstTradeParam,
            zombieTimeParam,
            removeLiquidityBeforeMaturityParam,
            closeLongFirstParam
        );
    }

    function test_zombie_interest_long_lp_edge_cases() external {
        // This test found a case that resulted in:
        // balanceOf(hyperdrive) = 0 and a sharePrice == 0
        // resulted in correcting the zombie interest formulat to:
        // dz * (c1 - c0)/c1
        {
            uint256 variableRateParam = 1056788241940997675;
            uint256 longTradeSizeParam = 106188581970341088534909779326808423763371022226296585668066343410313430049312;
            uint256 delayTimeFirstTradeParam = 0;
            uint256 zombieTimeParam = POSITION_DURATION;
            bool removeLiquidityBeforeMaturityParam = false;
            bool closeLongFirstParam = true;
            _test_zombie_interest_long_lp(
                variableRateParam,
                longTradeSizeParam,
                delayTimeFirstTradeParam,
                zombieTimeParam,
                removeLiquidityBeforeMaturityParam,
                closeLongFirstParam
            );
        }

        // This test demonstrates a case where the baseToken balance used to dip below MINIMUM_SHARE_RESERVES.
        // It also demonstrates a case where the zombieShares are nonzero.
        {
            uint256 variableRateParam = 1675919213486; // 0.000001675919213486
            uint256 longTradeSizeParam = 547096144916287995119834582695525599230103930298989461613742; // 209766864.405881102749203502
            uint256 delayTimeFirstTradeParam = 0;
            uint256 zombieTimeParam = 106; // 107
            bool removeLiquidityBeforeMaturityParam = false;
            bool closeLongFirstParam = true;
            _test_zombie_interest_long_lp(
                variableRateParam,
                longTradeSizeParam,
                delayTimeFirstTradeParam,
                zombieTimeParam,
                removeLiquidityBeforeMaturityParam,
                closeLongFirstParam
            );
        }
    }

    function _test_zombie_interest_long_lp(
        uint256 variableRateParam,
        uint256 longTradeSizeParam,
        uint256 delayTimeFirstTradeParam,
        uint256 zombieTimeParam,
        bool removeLiquidityBeforeMaturityParam,
        bool closeLongFirstParam
    ) internal {
        // Initialize the pool with capital.
        uint256 fixedRate = 0.035e18;
        deploy(bob, fixedRate, 1e18, 0, 0, 0, 0);
        initialize(bob, fixedRate, 2 * MINIMUM_SHARE_RESERVES);

        // Alice adds liquidity.
        uint256 initialLiquidity = 500_000_000e18;
        uint256 aliceLpShares = addLiquidity(alice, initialLiquidity);

        // Limit the fuzz testing to variableRate's less than or equal to 200%.
        int256 variableRate = int256(
            variableRateParam.normalizeToRange(0, 2e18)
        );

        // Ensure a feasible trade size.
        uint256 longTradeSize = longTradeSizeParam.normalizeToRange(
            2 * MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong() - MINIMUM_TRANSACTION_AMOUNT
        );

        // A random amount of time passes before the long is opened.
        uint256 delayTimeFirstTrade = delayTimeFirstTradeParam.normalizeToRange(
            0,
            CHECKPOINT_DURATION * 10
        );

        // A random amount of time passes after the term before the position is redeemed.
        uint256 zombieTime = zombieTimeParam.normalizeToRange(
            1,
            POSITION_DURATION
        );

        // Random amount of time passes before first trade.
        advanceTime(delayTimeFirstTrade, variableRate);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // Celine opens a long.
        (uint256 maturityTime, uint256 bondsReceived) = openLong(
            celine,
            longTradeSize
        );

        uint256 withdrawalProceeds;
        uint256 withdrawalShares;
        if (removeLiquidityBeforeMaturityParam) {
            // Alice removes liquidity.
            (withdrawalProceeds, withdrawalShares) = removeLiquidity(
                alice,
                aliceLpShares
            );
        }

        // One term passes and longs mature.
        advanceTime(POSITION_DURATION, variableRate);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // One term passes while we collect zombie interest. This is
        // necessary to show that the zombied base amount stays constant.
        uint256 zombieBaseBefore = hyperdrive
            .getPoolInfo()
            .zombieShareReserves
            .mulDown(hyperdrive.getPoolInfo().sharePrice);
        advanceTimeWithCheckpoints2(POSITION_DURATION, variableRate);
        uint256 zombieBaseAfter = hyperdrive
            .getPoolInfo()
            .zombieShareReserves
            .mulDown(hyperdrive.getPoolInfo().sharePrice);
        assertApproxEqAbs(zombieBaseBefore, zombieBaseAfter, 1e5);

        // A random amount of time passes and interest is collected.
        advanceTimeWithCheckpoints2(zombieTime, variableRate);

        uint256 longProceeds;
        if (closeLongFirstParam) {
            // Celina redeems her long late.
            longProceeds = closeLong(celine, maturityTime, bondsReceived);
            if (!removeLiquidityBeforeMaturityParam) {
                // Alice removes liquidity.
                (withdrawalProceeds, withdrawalShares) = removeLiquidity(
                    alice,
                    aliceLpShares
                );
            }
        } else {
            if (!removeLiquidityBeforeMaturityParam) {
                // Alice removes liquidity.
                (withdrawalProceeds, withdrawalShares) = removeLiquidity(
                    alice,
                    aliceLpShares
                );
            }
            // Celina redeems her long late.
            longProceeds = closeLong(celine, maturityTime, bondsReceived);
        }
        redeemWithdrawalShares(alice, withdrawalShares);

        // Verify that the baseToken balance is within the expected range.
        assertGe(
            baseToken.balanceOf(address(hyperdrive)),
            MINIMUM_SHARE_RESERVES
        );

        // If the share price is zero, then the hyperdrive balance is empty and there is a problem.
        uint256 sharePrice = hyperdrive.getPoolInfo().sharePrice;
        assertGt(sharePrice, 0);

        // Verify that the value represented in the share reserves is >= the actual amount in the contract.
        uint256 baseReserves = hyperdrive.getPoolInfo().shareReserves.mulDown(
            sharePrice
        );
        assertGe(baseToken.balanceOf(address(hyperdrive)), baseReserves);

        // Ensure that whatever is left in the zombie share reserves is <= hyperdrive contract - baseReserves.
        // This is an important check bc it implies ongoing solvency.
        assertLe(
            hyperdrive.getPoolInfo().zombieShareReserves.mulDown(sharePrice),
            baseToken.balanceOf(address(hyperdrive)) - baseReserves
        );
    }

    function test_zombie_interest_short_lp(
        uint256 variableRateParam,
        uint256 shortTradeSizeParam,
        uint256 delayTimeFirstTradeParam,
        uint256 zombieTimeParam,
        bool removeLiquidityBeforeMaturityParam,
        bool closeShortFirstParam
    ) external {
        _test_zombie_interest_short_lp(
            variableRateParam,
            shortTradeSizeParam,
            delayTimeFirstTradeParam,
            zombieTimeParam,
            removeLiquidityBeforeMaturityParam,
            closeShortFirstParam
        );
    }

    function test_zombie_interest_short_lp_edge_cases() external {
        // This demonstrates that Hyperdrive properly handles the
        // case where proceeds are zero.
        {
            uint256 variableRateParam = 0;
            uint256 shortTradeSizeParam = 0;
            uint256 delayTimeFirstTradeParam = 0;
            uint256 zombieTimeParam = 0;
            bool removeLiquidityBeforeMaturityParam = false;
            bool closeShortFirstParam = false;
            _test_zombie_interest_short_lp(
                variableRateParam,
                shortTradeSizeParam,
                delayTimeFirstTradeParam,
                zombieTimeParam,
                removeLiquidityBeforeMaturityParam,
                closeShortFirstParam
            );
        }

        // This test demonstrates a case where the baseReserves > hyperdrive
        // contract balance. This is ultimately caused by the difference in the
        // shareProceed calculation in _applyCheckpoint() at the exact moment of
        // maturtiy vs. when the short is finally redeemed. The problem was
        // fixed by waiting until the end of the bondFactor calc to divide it by
        // the current share price (previously we divided the c0 by c1.mulUp(c)).
        {
            uint256 variableRateParam = 5620429975859418641699674322; //1.859418638889459335
            uint256 shortTradeSizeParam = 1310781273383530713731927; //1310781.275383530713731927
            uint256 delayTimeFirstTradeParam = 28813180061722833364;
            uint256 zombieTimeParam = 53545089938242652621931217117333915620901721145447334647980366423087803150644;
            bool removeLiquidityBeforeMaturityParam = false;
            bool closeShortFirstParam = false;
            _test_zombie_interest_short_lp(
                variableRateParam,
                shortTradeSizeParam,
                delayTimeFirstTradeParam,
                zombieTimeParam,
                removeLiquidityBeforeMaturityParam,
                closeShortFirstParam
            );
        }

        // This edge case resulted in an arithmetic underflow.
        {
            uint256 variableRateParam = 6924978939;
            uint256 shortTradeSizeParam = 0;
            uint256 delayTimeFirstTradeParam = 1861560084099383131501047849308972;
            uint256 zombieTimeParam = 107109769472532495263397661882730987280282752509135183533614363784603189997220;
            bool removeLiquidityBeforeMaturityParam = false;
            bool closeShortFirstParam = false;
            _test_zombie_interest_short_lp(
                variableRateParam,
                shortTradeSizeParam,
                delayTimeFirstTradeParam,
                zombieTimeParam,
                removeLiquidityBeforeMaturityParam,
                closeShortFirstParam
            );
        }

        // This edge case results in the base balance being 1 wei less than the
        // base reserves.
        {
            uint256 variableRateParam = 8716533558;
            uint256 shortTradeSizeParam = 0;
            uint256 delayTimeFirstTradeParam = 101;
            uint256 zombieTimeParam = 72437868651368534594638639169;
            bool removeLiquidityBeforeMaturityParam = false;
            bool closeShortFirstParam = false;
            _test_zombie_interest_short_lp(
                variableRateParam,
                shortTradeSizeParam,
                delayTimeFirstTradeParam,
                zombieTimeParam,
                removeLiquidityBeforeMaturityParam,
                closeShortFirstParam
            );
        }
    }

    function _test_zombie_interest_short_lp(
        uint256 variableRateParam,
        uint256 shortTradeSizeParam,
        uint256 delayTimeFirstTradeParam,
        uint256 zombieTimeParam,
        bool removeLiquidityBeforeMaturityParam,
        bool closeShortFirstParam
    ) internal {
        // Initialize the pool with capital.
        uint256 fixedRate = 0.035e18;
        deploy(bob, fixedRate, 1e18, 0, 0, 0, 0);
        initialize(bob, fixedRate, 2 * MINIMUM_SHARE_RESERVES);

        // Alice adds liquidity.
        uint256 initialLiquidity = 500_000_000e18;
        uint256 aliceLpShares = addLiquidity(alice, initialLiquidity);

        // Limit the fuzz testing to variableRate's less than or equal to 200%.
        int256 variableRate = int256(
            variableRateParam.normalizeToRange(0, 2e18)
        );

        // Ensure a feasible trade size.
        uint256 shortTradeSize = shortTradeSizeParam.normalizeToRange(
            2 * MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxShort() - MINIMUM_TRANSACTION_AMOUNT
        );

        // A random amount of time passes before the short is opened.
        uint256 delayTimeFirstTrade = delayTimeFirstTradeParam.normalizeToRange(
            0,
            CHECKPOINT_DURATION * 10
        );

        // A random amount of time passes to pass after the term before the position is redeemed.
        uint256 zombieTime = zombieTimeParam.normalizeToRange(
            CHECKPOINT_DURATION / 5,
            POSITION_DURATION
        );

        // Random amount of time passes before first trade.
        advanceTime(delayTimeFirstTrade, variableRate);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // Celine opens a short.
        (uint256 maturityTime, ) = openShort(celine, shortTradeSize);

        uint256 withdrawalProceeds;
        uint256 withdrawalShares;
        if (removeLiquidityBeforeMaturityParam) {
            // Alice removes liquidity.
            (withdrawalProceeds, withdrawalShares) = removeLiquidity(
                alice,
                aliceLpShares
            );
        }

        // One term passes and shorts mature.
        advanceTime(POSITION_DURATION, variableRate);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // One term passes while we collect zombie interest. This is
        // necessary to show that the zombied base amount stays constant.
        uint256 zombieBaseBefore = hyperdrive
            .getPoolInfo()
            .zombieShareReserves
            .mulDown(hyperdrive.getPoolInfo().sharePrice);
        advanceTimeWithCheckpoints2(POSITION_DURATION, variableRate);
        uint256 zombieBaseAfter = hyperdrive
            .getPoolInfo()
            .zombieShareReserves
            .mulDown(hyperdrive.getPoolInfo().sharePrice);
        assertApproxEqAbs(zombieBaseBefore, zombieBaseAfter, 1e5);

        // A random amount of time passes and interest is collected.
        advanceTimeWithCheckpoints2(zombieTime, variableRate);

        uint256 shortProceeds;
        if (closeShortFirstParam) {
            // Celina redeems her short late.
            shortProceeds = closeShort(celine, maturityTime, shortTradeSize);
            if (!removeLiquidityBeforeMaturityParam) {
                // Alice removes liquidity.
                (withdrawalProceeds, withdrawalShares) = removeLiquidity(
                    alice,
                    aliceLpShares
                );
            }
        } else {
            if (!removeLiquidityBeforeMaturityParam) {
                // Alice removes liquidity.
                (withdrawalProceeds, withdrawalShares) = removeLiquidity(
                    alice,
                    aliceLpShares
                );
            }

            // Celina redeems her short late.
            shortProceeds = closeShort(celine, maturityTime, shortTradeSize);
        }
        redeemWithdrawalShares(alice, withdrawalShares);

        // Verify that the baseToken balance is within the expected range.
        assertGe(
            baseToken.balanceOf(address(hyperdrive)),
            MINIMUM_SHARE_RESERVES
        );

        // If the share price is zero, then the hyperdrive balance is empty and there is a problem.
        uint256 sharePrice = hyperdrive.getPoolInfo().sharePrice;
        assertGt(sharePrice, 0);

        // Verify that the value represented in the share reserves is >= the actual amount in the contract.
        uint256 baseReserves = hyperdrive.getPoolInfo().shareReserves.mulDown(
            sharePrice
        );
        assertGe(baseToken.balanceOf(address(hyperdrive)) + 1, baseReserves);

        // Ensure that whatever is left in the zombie share reserves is
        // less than `balance(hyperdrive) - baseReserves`.
        // This is an important check bc it implies ongoing solvency.
        assertLe(
            hyperdrive.getPoolInfo().zombieShareReserves.mulDown(sharePrice),
            baseToken.balanceOf(address(hyperdrive)) + 10 wei - baseReserves
        );
    }

    // This test just demonstrates that shorts redeemed late do not receive
    // zombie interest.
    function test_zombie_short() external {
        // Initialize the pool with capital.
        deploy(bob, 0.035e18, 1e18, 0, 0, 0, 0);
        initialize(bob, 0.035e18, 2 * MINIMUM_SHARE_RESERVES);

        // Alice adds liquidity.
        uint256 initialLiquidity = 500_000_000e18;
        uint256 aliceLpShares = addLiquidity(alice, initialLiquidity);
        int256 variableRate = 0.1e18;

        // Ensure a feasible trade size.
        uint256 shortTradeSize = 1_000_000e18;

        // Celine opens a short.
        (uint256 maturityTime, ) = openShort(celine, shortTradeSize);

        // One term passes and shorts mature.
        advanceTime(POSITION_DURATION, variableRate);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // One term passes while we collect zombie interest. This is
        // necessary to show that the zombied base amount stays constant.
        uint256 zombieBaseBefore = hyperdrive
            .getPoolInfo()
            .zombieShareReserves
            .mulDown(hyperdrive.getPoolInfo().sharePrice);
        advanceTimeWithCheckpoints2(POSITION_DURATION, variableRate);
        uint256 zombieBaseAfter = hyperdrive
            .getPoolInfo()
            .zombieShareReserves
            .mulDown(hyperdrive.getPoolInfo().sharePrice);
        assertApproxEqAbs(zombieBaseBefore, zombieBaseAfter, 1e5);

        // Celina redeems her short late.
        closeShort(celine, maturityTime, shortTradeSize);

        // Alice removes liquidity.
        removeLiquidity(alice, aliceLpShares);
        baseToken.balanceOf(address(hyperdrive));

        // Verify that the baseToken balance is within the expected range.
        assertGe(
            baseToken.balanceOf(address(hyperdrive)),
            MINIMUM_SHARE_RESERVES
        );

        // If the share price is zero, then the hyperdrive balance is empty and there is a problem.
        uint256 sharePrice = hyperdrive.getPoolInfo().sharePrice;
        assertGt(sharePrice, 0);

        // Verify that the value represented in the share reserves is <= the actual amount in the contract.
        uint256 baseReserves = hyperdrive.getPoolInfo().shareReserves.mulDown(
            sharePrice
        );
        assertGe(baseToken.balanceOf(address(hyperdrive)), baseReserves);

        // Ensure that whatever is left in the zombie share reserves is <= hyperdrive contract - baseReserves.
        // This is an important check bc it implies ongoing solvency.
        assertLe(
            hyperdrive.getPoolInfo().zombieShareReserves.mulDown(sharePrice),
            baseToken.balanceOf(address(hyperdrive)) - baseReserves
        );
    }

    function test_skipped_checkpoint(
        uint256 variableRateParam,
        uint256 longTradeSizeParam
    ) external {
        uint256 fixedRate = 0.035e18;
        uint256 initialLiquidity = 500_000_000e18;

        uint256 zombieShareReserves1;
        uint256 shareReserves1;
        {
            // Initialize the pool with capital.
            deploy(bob, fixedRate, 1e18, 0, 0, 0, 0);
            initialize(bob, fixedRate, 2 * MINIMUM_SHARE_RESERVES);

            // Alice adds liquidity.
            addLiquidity(alice, initialLiquidity);

            // Limit the fuzz testing to variableRate's less than or equal to 200%.
            int256 variableRate = int256(
                variableRateParam.normalizeToRange(0, 2e18)
            );

            // Ensure a feasible trade size.
            uint256 longTradeSize = longTradeSizeParam.normalizeToRange(
                2 * MINIMUM_TRANSACTION_AMOUNT,
                hyperdrive.calculateMaxLong() - MINIMUM_TRANSACTION_AMOUNT
            );

            // Celine opens a long.
            openLong(celine, longTradeSize);

            // One term passes and longs mature.
            advanceTime(POSITION_DURATION, variableRate);
            hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

            // A checkpoints is missed.
            advanceTime(CHECKPOINT_DURATION, variableRate);

            // Several checkpoints are minted.
            advanceTimeWithCheckpoints2(3 * CHECKPOINT_DURATION, variableRate);

            // Advance time halfway to the next checkpoint.
            advanceTime(CHECKPOINT_DURATION / 2, variableRate);

            zombieShareReserves1 = hyperdrive.getPoolInfo().zombieShareReserves;
            shareReserves1 = hyperdrive.getPoolInfo().shareReserves;
        }

        uint256 zombieShareReserves2;
        uint256 shareReserves2;
        {
            // Initialize the pool with capital.
            deploy(bob, fixedRate, 1e18, 0, 0, 0, 0);
            assertEq(baseToken.balanceOf(address(hyperdrive)), 0);
            initialize(bob, fixedRate, 2 * MINIMUM_SHARE_RESERVES);

            // Alice adds liquidity.
            addLiquidity(alice, initialLiquidity);

            // Limit the fuzz testing to variableRate's less than or equal to 200%.
            int256 variableRate = int256(
                variableRateParam.normalizeToRange(0, 2e18)
            );

            // Ensure a feasible trade size.
            uint256 longTradeSize = longTradeSizeParam.normalizeToRange(
                2 * MINIMUM_TRANSACTION_AMOUNT,
                hyperdrive.calculateMaxLong() - MINIMUM_TRANSACTION_AMOUNT
            );

            // Celine opens a long.
            openLong(celine, longTradeSize);

            // One term passes and longs mature.
            advanceTime(POSITION_DURATION, variableRate);
            hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

            // Several checkpoints are minted.
            advanceTimeWithCheckpoints2(4 * CHECKPOINT_DURATION, variableRate);

            zombieShareReserves2 = hyperdrive.getPoolInfo().zombieShareReserves;
            shareReserves2 = hyperdrive.getPoolInfo().shareReserves;
        }

        // The zombie share reserves should be the same.
        assertApproxEqAbs(zombieShareReserves1, zombieShareReserves2, 5 wei);

        // The share reserves should be the same.
        assertApproxEqAbs(shareReserves1, shareReserves2, 5 wei);
    }
}
