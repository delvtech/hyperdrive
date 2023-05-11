// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract LPFairnessTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function test_lp_fairness_short_lp(
        uint256 fixedRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than 100%
        vm.assume(fixedRateParam < 1e18);

        // ensure a feasible trade size
        vm.assume(tradeSizeParam < 5_000_000e18);
        vm.assume(tradeSizeParam > 0.00001e18);

        // variable interest rate earned by the pool
        int256 variableRate = int256(fixedRateParam);

        // fixed interest rate the pool pays the longs
        uint256 fixedRate = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);

        // Celine opens a short.
        uint256 bondsShorted = tradeSizeParam;
        (, uint256 baseSpent) = openShort(celine, bondsShorted);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // The term passes.
        advanceTime(POSITION_DURATION, variableRate);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + contribution + baseSpent,
            variableRate,
            POSITION_DURATION
        );

        // Calculate the total short interest.
        (, int256 shortInterest) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted,
            variableRate,
            POSITION_DURATION
        );

        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = uint256(poolValue - baseSpent)
            .mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));

        // calculate the portion of the fixed interest that bob earned
        uint256 fixedInterestEarned = baseSpent.mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the portion of the variable interest that bob owes
        uint256 variableInterestOwed = uint256(shortInterest).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest +
            fixedInterestEarned -
            variableInterestOwed;

        // Bob removes liquidity
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 2e7);
    }

    function test_lp_fairness_short_short_lp(
        uint256 fixedRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than 100%
        vm.assume(fixedRateParam < 1e18);

        // ensure a feasible trade size
        vm.assume(tradeSizeParam < 5_000_000e18);
        vm.assume(tradeSizeParam > 0.00001e18);

        // variable interest rate earned by the pool
        int256 variableRate = int256(fixedRateParam);

        // fixed interest rate the pool pays the longs
        uint256 fixedRate = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);

        // Celine opens a short.
        uint256 bondsShorted = 5_000_000e18 - tradeSizeParam;
        (, uint256 baseSpent) = openShort(celine, bondsShorted);

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, variableRate);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + baseSpent,
            variableRate,
            POSITION_DURATION / 2
        );

        // Calculate the total short interest.
        (, int256 shortInterest) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted,
            variableRate,
            POSITION_DURATION / 2
        );

        // Celine opens another short.
        uint256 bondsShorted2 = tradeSizeParam;
        (, uint256 baseSpent2) = openShort(celine, bondsShorted2);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, variableRate);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue2, ) = HyperdriveUtils.calculateCompoundInterest(
            poolValue + contribution + baseSpent2,
            variableRate,
            POSITION_DURATION / 2
        );

        // Calculate the total short interest.
        (, int256 shortInterest2) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted + bondsShorted2 + uint256(shortInterest),
            variableRate,
            POSITION_DURATION / 2
        );

        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = uint256(
            poolValue2 - baseSpent2 - baseSpent
        ).mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));

        // calculate the portion of the fixed interest that bob earned
        uint256 fixedInterestEarned = (baseSpent + baseSpent2).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the portion of the variable interest that bob owes
        uint256 variableInterestOwed = uint256(shortInterest + shortInterest2)
            .mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));

        // calculate the expected withdrawal shares so they can be removed from the expected proceeds
        uint256 withdrawalShares = bondsShorted2.mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest +
            fixedInterestEarned -
            variableInterestOwed -
            withdrawalShares;

        // Bob removes liquidity
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 2e7);
    }

    function test_lp_fairness_long_lp(
        uint256 fixedRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than 100%
        vm.assume(fixedRateParam < 1e18);

        // ensure a feasible trade size
        vm.assume(tradeSizeParam < 5_000_000e18);
        vm.assume(tradeSizeParam > 0.00001e18);

        // variable interest rate earned by the pool
        int256 variableRate = int256(fixedRateParam);

        // fixed interest rate the pool pays the longs
        uint256 fixedRate = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);

        // Celine opens a long.
        uint256 baseSpent = tradeSizeParam;
        (, uint256 bondsPurchased) = openLong(celine, baseSpent);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // The term passes.
        advanceTime(POSITION_DURATION, variableRate);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + contribution + baseSpent,
            variableRate,
            POSITION_DURATION
        );

        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = (poolValue - baseSpent).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the portion of the fixed interest that bob owes
        uint256 fixedInterestOwed = (bondsPurchased - baseSpent).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest -
            fixedInterestOwed;

        // Ensure that if the new LP withdraws, they get their money back.
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 2e7);
    }

    function test_lp_fairness_long_long_lp(
        uint256 fixedRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit to variableRate's less than 100%
        vm.assume(fixedRateParam < 1e18);

        // ensure a feasible trade size
        vm.assume(tradeSizeParam < 5_000_000e18);
        vm.assume(tradeSizeParam > 0.00001e18);

        // variable interest rate earned by the pool
        int256 variableRate = int256(fixedRateParam);

        // fixed interest rate the pool pays the longs
        uint256 fixedRate = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);

        // Celine opens a long.
        uint256 baseSpent = 5_000_000e18 - tradeSizeParam;
        (, uint256 bondsPurchased) = openLong(celine, baseSpent);

        // 1/2 the term passes.
        advanceTime(POSITION_DURATION / 2, variableRate);
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + baseSpent,
            variableRate,
            POSITION_DURATION / 2
        );

        // Celine opens another long.
        uint256 baseSpent2 = tradeSizeParam;
        (, uint256 bondsPurchased2) = openLong(celine, baseSpent2);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // 1/2 the term passes.
        advanceTime(POSITION_DURATION / 2, variableRate);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue2, ) = HyperdriveUtils.calculateCompoundInterest(
            poolValue + contribution + baseSpent2,
            variableRate,
            POSITION_DURATION / 2
        );

        // calculate the portion of the pool's base reserves owned by bob.
        uint256 baseReserves = (poolValue2 - bondsPurchased).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the value of the outstanding bonds (with interest)
        (uint256 bondValueWithInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(
                bondsPurchased2,
                variableRate,
                POSITION_DURATION / 2
            );
        bondValueWithInterest = bondValueWithInterest.mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = baseReserves -
            bondValueWithInterest;

        // Ensure that if the new LP withdraws, they get their money back.
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e7);
    }

    function test_lp_fairness_short_long_lp(
        int256 variableRate,
        uint256 baseSpent2
    ) external {
        // limit the fuzz testing to variableRate's less than or equal to 100%
        variableRate = variableRate.normalizeToRange(0, 1e18);

        // ensure a feasible trade size
        baseSpent2 = baseSpent2.normalizeToRange(
            0.00001e18,
            5_000_000e18 - 0.000001e18
        );

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, 0.1e18, initialLiquidity);

        // Celine opens a short.
        uint256 bondsShorted = 5_000_000e18 - baseSpent2;
        (, uint256 baseSpent) = openShort(celine, bondsShorted);

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, variableRate);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + baseSpent,
            variableRate,
            POSITION_DURATION / 2
        );

        // Celine opens another long.
        (, uint256 bondsPurchased) = openLong(celine, baseSpent2);

        // Bob adds liquidity.
        uint256 lpShares;
        uint256 poolValue2;
        {
            uint256 contribution = 5_000_000e18;
            lpShares = addLiquidity(bob, contribution);

            // Calculate the value of the pool after interest is accrued.
            (poolValue2, ) = HyperdriveUtils.calculateCompoundInterest(
                poolValue + contribution + baseSpent2,
                variableRate,
                POSITION_DURATION / 2
            );
        }

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, variableRate);

        // Calculate the total short interest.
        (, int256 shortInterest) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted,
            variableRate,
            POSITION_DURATION
        );

        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = uint256(poolValue2 - baseSpent)
            .mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));

        // calculate the portion of the fixed interest that bob earned
        uint256 fixedInterestEarned = baseSpent.mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the portion of the variable interest that bob owes
        uint256 variableInterestOwed = uint256(shortInterest).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the portion of the fixed interest that bob owes
        (uint256 fixedInterestOwed, ) = HyperdriveUtils
            .calculateCompoundInterest(
                bondsPurchased,
                variableRate,
                POSITION_DURATION / 2
            );
        fixedInterestOwed = fixedInterestOwed.mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest +
            fixedInterestEarned -
            variableInterestOwed -
            fixedInterestOwed;

        // Bob removes liquidity
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 2e7);
    }

    function test_lp_fairness_long_short_lp(
        uint256 fixedRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit to variableRate's less than 100%
        vm.assume(fixedRateParam < 1e18);

        // ensure a feasible trade size
        vm.assume(tradeSizeParam < 5_000_000e18);
        vm.assume(tradeSizeParam > 0.00001e18);

        // variable interest rate earned by the pool
        int256 variableRate = int256(fixedRateParam);

        // fixed interest rate the pool pays the longs
        uint256 fixedRate = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);

        // Celine opens a long.
        uint256 baseSpent = 5_000_000e18 - tradeSizeParam;
        (, uint256 bondsPurchased) = openLong(celine, baseSpent);

        // 1/2 the term passes.
        advanceTime(POSITION_DURATION / 2, variableRate);
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + baseSpent,
            variableRate,
            POSITION_DURATION / 2
        );

        // Celine opens a short.
        uint256 bondsShorted = tradeSizeParam;
        (, uint256 baseSpent2) = openShort(celine, bondsShorted);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // 1/2 the term passes.
        advanceTime(POSITION_DURATION / 2, variableRate);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue2, ) = HyperdriveUtils.calculateCompoundInterest(
            poolValue + contribution + baseSpent2,
            variableRate,
            POSITION_DURATION / 2
        );

        // Calculate the total short interest.
        (, int256 shortInterest) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted,
            variableRate,
            POSITION_DURATION / 2
        );

        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = (poolValue2 - baseSpent2 - baseSpent)
            .mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));

        // calculate the portion of the fixed interest that bob earned
        uint256 fixedInterestEarned = baseSpent2.mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the portion of the variable interest that bob owes
        uint256 variableInterestOwed = uint256(shortInterest).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the portion of the fixed interest that bob owes
        uint256 fixedInterestOwed = (bondsPurchased - baseSpent).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the expected withdrawal shares so they can be removed from the expected proceeds
        uint256 withdrawalShares = bondsShorted.mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest +
            fixedInterestEarned -
            variableInterestOwed -
            fixedInterestOwed -
            withdrawalShares;

        // Ensure that if the new LP withdraws, they get their money back.
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 2e7);
    }
}
