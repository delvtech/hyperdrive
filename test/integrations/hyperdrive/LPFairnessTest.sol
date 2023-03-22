// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import "test/utils/Lib.sol";
import "forge-std/console2.sol";

contract LPFairnessTest is HyperdriveTest {
    // TODO: remove this
    using Lib for *;
    using FixedPointMath for uint256;

    function test_lp_fairness_short_lp(
        uint256 param1,
        uint256 param2
    ) external {
        // limit the fuzz testing to apy's less than 100%
        vm.assume(param1 < 1e18);

        // ensure a feasible trade size
        vm.assume(param2 < 5_000_000e18);
        vm.assume(param2 > .00001e18);

        // variable interest rate earned by the pool
        int256 apy = int256(param1);

        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);
        {
            // Store the pool APR before Celine opens a short.
            uint256 aprBefore = HyperdriveUtils.calculateAPRFromReserves(
                hyperdrive
            );
            console2.log("aprBefore", aprBefore.toString(18));
        }

        // Celine opens a short.
        uint256 bondsShorted = param2;
        console2.log("bondsShorted", bondsShorted.toString(18));
        (, uint256 baseSpent) = openShort(celine, bondsShorted);
        console2.log("baseSpent", baseSpent.toString(18));
        {
            // Store the pool APR after Celine opens a short.
            uint256 aprAfter = HyperdriveUtils.calculateAPRFromReserves(
                hyperdrive
            );
            console2.log("aprAfter", aprAfter.toString(18));
        }

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);

        // The term passes.
        advanceTime(POSITION_DURATION, apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue, int256 poolInterest) = HyperdriveUtils
            .calculateCompoundInterest(
                initialLiquidity + contribution + baseSpent,
                apy,
                POSITION_DURATION
            );
        console2.log("poolInterest", poolInterest.toString(18));
        console2.log("poolValue", poolValue.toString(18));

        // Calculate the value of the short after interest is accrued.
        (, int256 shortInterest) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted,
            apy,
            POSITION_DURATION
        );

        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = uint256(poolValue - baseSpent)
            .mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));
        console2.log(
            "contributionWithInterest",
            contributionWithInterest.toString(18)
        );

        // calculate the portion of the fixed interest that bob earned
        uint256 fixedInterestEarned = baseSpent.mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );
        console2.log("fixedInterestEarned", fixedInterestEarned.toString(18));

        // calculate the portion of the variable interest that bob owes
        uint256 variableInterestOwed = uint256(shortInterest).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );
        console2.log("variableInterestOwed", variableInterestOwed.toString(18));

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest +
            fixedInterestEarned -
            variableInterestOwed;
        console2.log(
            "expectedWithdrawalProceeds",
            expectedWithdrawalProceeds.toString(18)
        );

        // Bob removes liquidity
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e8);
    }

    function test_lp_fairness_short_short_lp(
        uint256 param1,
        uint256 param2
    ) external {
        // limit the fuzz testing to apy's less than 100%
        vm.assume(param1 < 1e18);

        // ensure a feasible trade size
        vm.assume(param2 < 5_000_000e18);
        vm.assume(param2 > .00001e18);

        // variable interest rate earned by the pool
        int256 apy = int256(param1);

        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);
        {
            // Store the pool APR before Celine opens a short.
            uint256 aprBefore = HyperdriveUtils.calculateAPRFromReserves(
                hyperdrive
            );
            console2.log("aprBefore", aprBefore.toString(18));
        }

        // Celine opens a short.
        uint256 bondsShorted = 5_000_000e18 - param2;
        console2.log("bondsShorted", bondsShorted.toString(18));
        (, uint256 baseSpent) = openShort(celine, bondsShorted);
        console2.log("baseSpent", baseSpent.toString(18));
        {
            // Store the pool APR after Celine opens a short.
            uint256 aprAfter = HyperdriveUtils.calculateAPRFromReserves(
                hyperdrive
            );
            console2.log("aprAfter", aprAfter.toString(18));
        }

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + baseSpent,
            apy,
            POSITION_DURATION / 2
        );
        console2.log("poolValue", poolValue.toString(18));

        // Calculate the value of the pool after interest is accrued.
        (, int256 shortInterest) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted,
            apy,
            POSITION_DURATION / 2
        );

        // Celine opens another short.
        uint256 bondsShorted2 = param2;
        console2.log("bondsShorted2", bondsShorted2.toString(18));
        (, uint256 baseSpent2) = openShort(celine, bondsShorted2);
        console2.log("baseSpent2", baseSpent2.toString(18));

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);
        console2.log("lpShares", lpShares.toString(18));

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue2, ) = HyperdriveUtils.calculateCompoundInterest(
            poolValue + contribution + baseSpent2,
            apy,
            POSITION_DURATION / 2
        );
        console2.log("poolValue2", poolValue2.toString(18));

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
        console2.log(
            "contributionWithInterest",
            contributionWithInterest.toString(18)
        );

        // calculate the portion of the fixed interest that bob earned
        uint256 fixedInterestEarned = (baseSpent + baseSpent2).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );
        console2.log("fixedInterestEarned", fixedInterestEarned.toString(18));

        // calculate the portion of the variable interest that bob owes
        uint256 variableInterestOwed = uint256(shortInterest + shortInterest2)
            .mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));
        console2.log("variableInterestOwed", variableInterestOwed.toString(18));

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
        console2.log(
            "expectedWithdrawalProceeds",
            expectedWithdrawalProceeds.toString(18)
        );

        // Bob removes liquidity
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e8);
    }

    function test_lp_fairness_long_lp(uint256 param1, uint256 param2) external {
        // limit the fuzz testing to apy's less than 100%
        vm.assume(param1 < 1e18);

        // ensure a feasible trade size
        vm.assume(param2 < 5_000_000e18);
        vm.assume(param2 > .00001e18);

        // variable interest rate earned by the pool
        int256 apy = int256(param1);

        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);

        // Store the pool APR before Celine opens a long.
        uint256 aprBeforeLong = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        console2.log("aprBeforeLong", aprBeforeLong.toString(18));

        // Celine opens a long.
        uint256 baseSpent = param2;
        console2.log("baseSpent", baseSpent.toString(18));
        (, uint256 bondsPurchased) = openLong(celine, baseSpent);
        console2.log("bondsPurchased", bondsPurchased.toString(18));

        // Store the pool APR after Celine opens a short.
        uint256 aprAfterLong = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        console2.log("aprAfterLong", aprAfterLong.toString(18));

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
        console2.log("poolValue", poolValue.toString(18));

        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = (poolValue - baseSpent).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );
        console2.log(
            "contributionWithInterest",
            contributionWithInterest.toString(18)
        );

        // calculate the portion of the fixed interest that bob owes
        uint256 fixedInterestOwed = (bondsPurchased - baseSpent).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );
        console2.log("fixedInterestOwed", fixedInterestOwed.toString(18));

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest -
            fixedInterestOwed;
        console2.log(
            "expectedWithdrawalProceeds",
            expectedWithdrawalProceeds.toString(18)
        );

        // Ensure that if the new LP withdraws, they get their money back.
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e8);
    }

    function test_lp_fairness_long_long_lp(
        uint256 param1,
        uint256 param2
    ) external {
        // limit to apy's less than 100%
        vm.assume(param1 < 1e18);

        // ensure a feasible trade size
        vm.assume(param2 < 5_000_000e18);
        vm.assume(param2 > .00001e18);

        //uint256 param1 = 0.01e18;
        //uint256 param2 = 1000;
        console2.log("param2", param2.toString(18));

        // variable interest rate earned by the pool
        int256 apy = int256(param1);
        console2.log("apy", apy.toString(18));

        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);
        {
            // Store the pool APR before Celine opens a long.
            uint256 aprBeforeLong = HyperdriveUtils.calculateAPRFromReserves(
                hyperdrive
            );
            console2.log("aprBeforeLong", aprBeforeLong.toString(18));
        }

        // Celine opens a long.
        uint256 baseSpent = 5_000_000e18 - param2;
        console2.log("baseSpent", baseSpent.toString(18));
        (, uint256 bondsPurchased) = openLong(celine, baseSpent);
        console2.log("bondsPurchased", bondsPurchased.toString(18));

        {
            // Store the pool APR after Celine opens a short.
            uint256 aprAfterLong = HyperdriveUtils.calculateAPRFromReserves(
                hyperdrive
            );
            console2.log("aprAfterLong", aprAfterLong.toString(18));
        }
        // 1/2 the term passes.
        advanceTime(POSITION_DURATION / 2, apy);
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + baseSpent,
            apy,
            POSITION_DURATION / 2
        );

        // Celine opens another long.
        uint256 baseSpent2 = param2;
        console2.log("baseSpent2", baseSpent2.toString(18));
        (, uint256 bondsPurchased2) = openLong(celine, baseSpent2);
        console2.log("bondsPurchased2", bondsPurchased2.toString(18));

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
        console2.log("poolValue2", poolValue2.toString(18));

        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = (poolValue2 - baseSpent2 - baseSpent)
            .mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));
        console2.log(
            "contributionWithInterest",
            contributionWithInterest.toString(18)
        );

        // calculate the portion of the fixed interest that bob owes
        uint256 fixedInterestOwed = (bondsPurchased +
            bondsPurchased2 -
            baseSpent2 -
            baseSpent).mulDivDown(
                lpShares,
                hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
            );
        console2.log("fixedInterestOwed", fixedInterestOwed.toString(18));

        // calculate the expected withdrawal shares so they can be removed from the expected proceeds
        uint256 withdrawalShares = bondsPurchased2.mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );
        console2.log("withdrawalShares", withdrawalShares.toString(18));

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest -
            fixedInterestOwed;
        console2.log(
            "expectedWithdrawalProceeds",
            expectedWithdrawalProceeds.toString(18)
        );

        // Ensure that if the new LP withdraws, they get their money back.
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e8);
    }

    function test_lp_fairness_short_long_lp(
        uint256 param1,
        uint256 param2
    ) external {
        // limit the fuzz testing to apy's less than 100%
        vm.assume(param1 < 1e18);

        // ensure a feasible trade size
        vm.assume(param2 < 5_000_000e18);
        vm.assume(param2 > .00001e18);

        // variable interest rate earned by the pool
        int256 apy = int256(param1);

        // fixed interest rate the pool pays the longs
        uint256 apr = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        initialize(alice, apr, initialLiquidity);
        {
            // Store the pool APR before Celine opens a short.
            uint256 aprBefore = HyperdriveUtils.calculateAPRFromReserves(
                hyperdrive
            );
            console2.log("aprBefore", aprBefore.toString(18));
        }

        // Celine opens a short.
        uint256 bondsShorted = 5_000_000e18 - param2;
        console2.log("bondsShorted", bondsShorted.toString(18));
        (, uint256 baseSpent) = openShort(celine, bondsShorted);
        console2.log("baseSpent", baseSpent.toString(18));
        {
            // Store the pool APR after Celine opens a short.
            uint256 aprAfter = HyperdriveUtils.calculateAPRFromReserves(
                hyperdrive
            );
            console2.log("aprAfter", aprAfter.toString(18));
        }

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
            initialLiquidity + baseSpent,
            apy,
            POSITION_DURATION / 2
        );
        console2.log("poolValue", poolValue.toString(18));

        // Celine opens another long.
        uint256 baseSpent2 = param2;
        console2.log("baseSpent2", baseSpent2.toString(18));
        (, uint256 bondsPurchased) = openLong(celine, baseSpent2);
        console2.log("bondsPurchased", bondsPurchased.toString(18));

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 lpShares = addLiquidity(bob, contribution);
        console2.log("lpShares", lpShares.toString(18));

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, apy);

        // Calculate the value of the pool after interest is accrued.
        (uint256 poolValue2, ) = HyperdriveUtils.calculateCompoundInterest(
            poolValue + contribution + baseSpent2,
            apy,
            POSITION_DURATION / 2
        );
        console2.log("poolValue2", poolValue2.toString(18));

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
        console2.log(
            "contributionWithInterest",
            contributionWithInterest.toString(18)
        );

        // calculate the portion of the fixed interest that bob earned
        uint256 fixedInterestEarned = baseSpent.mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );
        console2.log("fixedInterestEarned", fixedInterestEarned.toString(18));

        // calculate the portion of the variable interest that bob owes
        uint256 variableInterestOwed = uint256(shortInterest)
            .mulDivDown(lpShares, hyperdrive.totalSupply(AssetId._LP_ASSET_ID));
        console2.log("variableInterestOwed", variableInterestOwed.toString(18));

        // calculate the portion of the fixed interest that bob owes
        uint256 fixedInterestOwed = (bondsPurchased - baseSpent2).mulDivDown(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );
        console2.log("fixedInterestOwed", fixedInterestOwed.toString(18));

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = contributionWithInterest +
            fixedInterestEarned -
            variableInterestOwed -
            fixedInterestOwed;
        console2.log(
            "expectedWithdrawalProceeds",
            expectedWithdrawalProceeds.toString(18)
        );

        // Bob removes liquidity
        uint256 withdrawalProceeds = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e8);
    }
    
}
