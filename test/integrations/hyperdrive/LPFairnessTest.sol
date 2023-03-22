// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";

contract LPFairnessTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_lp_fairness_short_lp(
        uint256 param1,
        uint256 param2
    ) external {
        // limit the fuzz testing to apy's less than 100%
        vm.assume(param1 < 1e18);

        // ensure a feasible trade size
        vm.assume(param2 < 5_000_000e18);
        vm.assume(param2 > 0.00001e18);

        // variable interest rate earned by the pool
        int256 apy = int256(param1);

        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);

        // Celine opens a short.
        uint256 bondsShorted = param2;
        (, uint256 baseSpent) = openShort(celine, bondsShorted);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // The term passes.
        advanceTime(POSITION_DURATION, apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + contribution + baseSpent,
            apy,
            POSITION_DURATION
        );

        // Calculate the value of the short after interest is accrued.
        (, int256 shortInterest) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted,
            apy,
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
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e7);
    }

    function test_lp_fairness_short_short_lp(
        uint256 param1,
        uint256 param2
    ) external {
        // limit the fuzz testing to apy's less than 100%
        vm.assume(param1 < 1e18);

        // ensure a feasible trade size
        vm.assume(param2 < 5_000_000e18);
        vm.assume(param2 > 0.00001e18);

        // variable interest rate earned by the pool
        int256 apy = int256(param1);

        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);

        // Celine opens a short.
        uint256 bondsShorted = 5_000_000e18 - param2;
        (, uint256 baseSpent) = openShort(celine, bondsShorted);

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + baseSpent,
            apy,
            POSITION_DURATION / 2
        );

        // Calculate the value of the short after interest is accrued.
        (, int256 shortInterest) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted,
            apy,
            POSITION_DURATION / 2
        );

        // Celine opens another short.
        uint256 bondsShorted2 = param2;
        (, uint256 baseSpent2) = openShort(celine, bondsShorted2);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue2, ) = HyperdriveUtils.calculateCompoundInterest(
            poolValue + contribution + baseSpent2,
            apy,
            POSITION_DURATION / 2
        );

        // Calculate the value of the short after interest is accrued.
        (, int256 shortInterest2) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted + bondsShorted2 + uint256(shortInterest),
            apy,
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
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e7);
    }

    function test_lp_fairness_long_lp(uint256 param1, uint256 param2) external {
        // limit the fuzz testing to apy's less than 100%
        vm.assume(param1 < 1e18);

        // ensure a feasible trade size
        vm.assume(param2 < 5_000_000e18);
        vm.assume(param2 > 0.00001e18);

        // variable interest rate earned by the pool
        int256 apy = int256(param1);

        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);

        // Celine opens a long.
        uint256 baseSpent = param2;
        (, uint256 bondsPurchased) = openLong(celine, baseSpent);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // The term passes.
        advanceTime(POSITION_DURATION, apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + contribution + baseSpent,
            apy,
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
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e7);
    }

    function test_lp_fairness_long_long_lp(
        uint256 param1,
        uint256 param2
    ) external {
        // limit to apy's less than 100%
        vm.assume(param1 < 1e18);

        // ensure a feasible trade size
        vm.assume(param2 < 5_000_000e18);
        vm.assume(param2 > 0.00001e18);

        // variable interest rate earned by the pool
        int256 apy = int256(param1);

        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);

        // Celine opens a long.
        uint256 baseSpent = 5_000_000e18 - param2;
        (, uint256 bondsPurchased) = openLong(celine, baseSpent);

        // 1/2 the term passes.
        advanceTime(POSITION_DURATION / 2, apy);
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + baseSpent,
            apy,
            POSITION_DURATION / 2
        );

        // Celine opens another long.
        uint256 baseSpent2 = param2;
        (, uint256 bondsPurchased2) = openLong(celine, baseSpent2);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // 1/2 the term passes.
        advanceTime(POSITION_DURATION / 2, apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue2, ) = HyperdriveUtils.calculateCompoundInterest(
            poolValue + contribution + baseSpent2,
            apy,
            POSITION_DURATION / 2
        );

        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = (poolValue2 - baseSpent2 - baseSpent)
            .mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));

        // calculate the portion of the fixed interest that bob owes
        uint256 fixedInterestOwed = (bondsPurchased +
            bondsPurchased2 -
            baseSpent2 -
            baseSpent).mulDivDown(
                lpShares,
                hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
            );

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest -
            fixedInterestOwed;

        // Ensure that if the new LP withdraws, they get their money back.
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e7);
    }

    function test_lp_fairness_short_long_lp(
        uint256 param1,
        uint256 param2
    ) external {
        // limit the fuzz testing to apy's less than 100%
        vm.assume(param1 < 1e18);

        // ensure a feasible trade size
        vm.assume(param2 < 5_000_000e18);
        vm.assume(param2 > 0.00001e18);

        // variable interest rate earned by the pool
        int256 apy = int256(param1);

        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);

        // Celine opens a short.
        uint256 bondsShorted = 5_000_000e18 - param2;
        (, uint256 baseSpent) = openShort(celine, bondsShorted);

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + baseSpent,
            apy,
            POSITION_DURATION / 2
        );

        // Celine opens another long.
        uint256 baseSpent2 = param2;
        (, uint256 bondsPurchased) = openLong(celine, baseSpent2);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue2, ) = HyperdriveUtils.calculateCompoundInterest(
            poolValue + contribution + baseSpent2,
            apy,
            POSITION_DURATION / 2
        );

        // Calculate the value of the short after interest is accrued.
        (, int256 shortInterest) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted,
            apy,
            POSITION_DURATION
        );

        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = uint256(
            poolValue2 - baseSpent2 - baseSpent
        ).mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));

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
        uint256 fixedInterestOwed = (bondsPurchased - baseSpent2).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest +
            fixedInterestEarned -
            variableInterestOwed -
            fixedInterestOwed;

        // Bob removes liquidity
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e7);
    }

    function test_lp_fairness_long_short_lp(
        uint256 param1,
        uint256 param2
    ) external {
        // limit to apy's less than 100%
        vm.assume(param1 < 1e18);

        // ensure a feasible trade size
        vm.assume(param2 < 5_000_000e18);
        vm.assume(param2 > 0.00001e18);

        // variable interest rate earned by the pool
        int256 apy = int256(param1);

        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);

        // Celine opens a long.
        uint256 baseSpent = 5_000_000e18 - param2;
        (, uint256 bondsPurchased) = openLong(celine, baseSpent);

        // 1/2 the term passes.
        advanceTime(POSITION_DURATION / 2, apy);
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + baseSpent,
            apy,
            POSITION_DURATION / 2
        );

        // Celine opens a short.
        uint256 bondsShorted = param2;
        (, uint256 baseSpent2) = openShort(celine, bondsShorted);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // 1/2 the term passes.
        advanceTime(POSITION_DURATION / 2, apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue2, ) = HyperdriveUtils.calculateCompoundInterest(
            poolValue + contribution + baseSpent2,
            apy,
            POSITION_DURATION / 2
        );

        // Calculate the value of the short after interest is accrued.
        (, int256 shortInterest) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted,
            apy,
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
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e7);
    }
}
