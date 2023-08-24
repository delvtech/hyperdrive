// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

import "forge-std/console2.sol";

contract LPFairnessTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Deploy Hyperdrive with a small minimum share reserves so that it is
        // negligible relative to our error tolerances.
        IHyperdrive.PoolConfig memory config = testConfig(0.05e18);
        config.minimumShareReserves = 1e6;
        deploy(deployer, config);
    }

    function test_lp_fairness_short_lp(
        uint256 variableRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than or equal to 250%
        variableRateParam = variableRateParam.normalizeToRange(0, 2.5e18);

        // ensure a feasible trade size
        tradeSizeParam = tradeSizeParam.normalizeToRange(
            0.00001e18,
            5_000_000e18 - 0.000001e18
        );

        // variable interest rate earned by the pool
        int256 variableRate = int256(variableRateParam);

        // fixed interest rate the pool pays the longs
        uint256 fixedRate = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        uint256 aliceLpShares = initialize(alice, fixedRate, initialLiquidity);

        // Celine opens a short.
        uint256 bondsShorted = tradeSizeParam;
        (uint256 maturityTime, ) = openShort(
            celine,
            bondsShorted
        );

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 bobLpShares = addLiquidity(bob, contribution);

        // The term passes.
        advanceTimeWithCheckpoints(POSITION_DURATION, variableRate);

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = calculateBaseLpProceeds(bobLpShares);

        // Bob removes liquidity
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e9);

        // Celine closes her short.
        closeShort(celine, maturityTime, bondsShorted);

        // calculate the expected withdrawal proceeds
        expectedWithdrawalProceeds = calculateBaseLpProceeds(aliceLpShares);

        // Alice removes liquidity
        (withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e9);
    }

    function test_lp_fairness_short_short_lp(
        uint256 variableRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than or equal to 250%
        variableRateParam = variableRateParam.normalizeToRange(0, 2.5e18);

        // ensure a feasible trade size
        tradeSizeParam = tradeSizeParam.normalizeToRange(
            0.00001e18,
            5_000_000e18 - 0.000001e18
        );

        // variable interest rate earned by the pool
        int256 variableRate = int256(variableRateParam);

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        uint256 aliceLpShares = initialize(alice, 0.10e18, initialLiquidity);

        // Celine opens a short.
        uint256 bondsShorted = 5_000_000e18 - tradeSizeParam;
        openShort(celine, bondsShorted);

        // 1/2 term passes.
        advanceTimeWithCheckpoints(POSITION_DURATION / 2, variableRate);

        // Celine opens another short.
        uint256 bondsShorted2 = tradeSizeParam;
        openShort(celine, bondsShorted2);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 bobLpShares = addLiquidity(bob, contribution);

        // 1/2 term passes.
        advanceTimeWithCheckpoints(POSITION_DURATION / 2, variableRate);

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = calculateBaseLpProceeds(bobLpShares);

        // Bob removes liquidity
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e9);

        // calculate the expected withdrawal proceeds
        expectedWithdrawalProceeds = calculateBaseLpProceeds(aliceLpShares);

        // Alice removes liquidity
        (withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e9);
    }

    function test_lp_fairness_long_lp(
        uint256 variableRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than or equal to 250%
        variableRateParam = variableRateParam.normalizeToRange(0, 2.5e18);

        // ensure a feasible trade size
        tradeSizeParam = tradeSizeParam.normalizeToRange(
            0.00001e18,
            5_000_000e18 - 0.000001e18
        );

        // variable interest rate earned by the pool
        int256 variableRate = int256(variableRateParam);

        // fixed interest rate the pool pays the longs
        uint256 fixedRate = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        uint256 aliceLpShares = initialize(alice, fixedRate, initialLiquidity);

        // Celine opens a long.
        uint256 baseSpent = tradeSizeParam;
        (uint256 maturityTime, uint256 bondsPurchased) = openLong(
            celine,
            baseSpent
        );

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 bobLpShares = addLiquidity(bob, contribution);

        // The term passes.
        advanceTimeWithCheckpoints(POSITION_DURATION, variableRate);

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = calculateBaseLpProceeds(bobLpShares);

        // Ensure that if the new LP withdraws, they get their money back.
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e9);

        // Celine closes her long.
        closeLong(celine, maturityTime, bondsPurchased);

        // calculate the expected withdrawal proceeds
        expectedWithdrawalProceeds = calculateBaseLpProceeds(aliceLpShares);

        // Alice removes liquidity
        (withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e9);
    }

    function test_lp_fairness_long_long_lp(
        uint256 variableRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than or equal to 250%
        variableRateParam = variableRateParam.normalizeToRange(0, 2.5e18);

        // ensure a feasible trade size
        tradeSizeParam = tradeSizeParam.normalizeToRange(
            0.00001e18,
            5_000_000e18 - 0.000001e18
        );

        // variable interest rate earned by the pool
        int256 variableRate = int256(variableRateParam);

        // fixed interest rate the pool pays the longs
        uint256 fixedRate = 0.10e18;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        uint256 aliceLpShares = initialize(alice, fixedRate, initialLiquidity);

        // Celine opens a long.
        uint256 baseSpent = 5_000_000e18 - tradeSizeParam;
        openLong(celine, baseSpent);

        // 1/2 the term passes.
        advanceTimeWithCheckpoints(POSITION_DURATION / 2, variableRate);

        // Celine opens another long.
        uint256 baseSpent2 = tradeSizeParam;
        openLong(celine, baseSpent2);


        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 bobLpShares = addLiquidity(bob, contribution);

        // 1/2 the term passes.
        advanceTimeWithCheckpoints(POSITION_DURATION / 2, variableRate);
        

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = calculateBaseLpProceeds(
            bobLpShares
        );

        // Bob removes liquidity
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e9);

        // calculate alice's expected withdrawal proceeds
        expectedWithdrawalProceeds = calculateBaseLpProceeds(aliceLpShares);

        // Alice removes liquidity
        (withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e9);
    }

    function test_lp_fairness_short_long_lp(
        int256 variableRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than or equal to 250%
        variableRateParam = variableRateParam.normalizeToRange(0, 2.5e18);

        // ensure a feasible trade size
        tradeSizeParam = tradeSizeParam.normalizeToRange(
            0.00001e18,
            5_000_000e18 - 0.000001e18
        );

        uint256 poolValue = 0;
        uint256 bondsShorted = 0;
        uint256 baseSpent = 0;
        uint256 aliceLpShares = 0;
        {
            // Initialize the pool with capital.
            uint256 initialLiquidity = 5_000_000e18;
            aliceLpShares = initialize(alice, 0.1e18, initialLiquidity);

            // Celine opens a short.
            bondsShorted = 5_000_000e18 - tradeSizeParam;
            (, baseSpent) = openShort(celine, bondsShorted);

            // 1/2 term passes.
            advanceTime(POSITION_DURATION / 2, variableRateParam);

            // Calculate the value of the pool after interest is accrued.
            (poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
                initialLiquidity + baseSpent,
                variableRateParam,
                POSITION_DURATION / 2
            );
        }

        // Celine opens another long.
        (, uint256 bondsPurchased) = openLong(celine, tradeSizeParam);

        // Bob adds liquidity.
        uint256 bobLpShares;
        uint256 poolValue2;
        {
            uint256 contribution = 5_000_000e18;
            bobLpShares = addLiquidity(bob, contribution);

            // Calculate the value of the pool after interest is accrued.
            (poolValue2, ) = HyperdriveUtils.calculateCompoundInterest(
                poolValue + contribution + tradeSizeParam,
                variableRateParam,
                POSITION_DURATION / 2
            );
        }

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, variableRateParam);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint());

        // Calculate the total short interest.
        (, int256 shortInterest) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted,
            variableRateParam,
            POSITION_DURATION
        );

        // Calculate the total amount of fixed interest owed
        (uint256 totalFixedInterestOwed, ) = HyperdriveUtils
            .calculateCompoundInterest(
                bondsPurchased,
                variableRateParam,
                POSITION_DURATION / 2
            );

        // calculate the portion of the pool's value (after interest) that bob contributed.
        uint256 contributionWithInterest = uint256(poolValue2 - baseSpent)
            .mulDivDown(
                bobLpShares,
                hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
            );

        // calculate the portion of the fixed interest that bob earned
        uint256 fixedInterestEarned = baseSpent.mulDivDown(
            bobLpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the portion of the variable interest that bob owes
        uint256 variableInterestOwed = uint256(shortInterest).mulDivDown(
            bobLpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the portion of the fixed interest that bob owes
        uint256 fixedInterestOwed = totalFixedInterestOwed.mulDivDown(
            bobLpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = calculateBaseLpProceeds(
            bobLpShares
        );

        // calculate alice's proportion of LP shares
        uint256 aliceLpProportion = aliceLpShares.divDown(
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );

        // Bob removes liquidity
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e9);

        // calculate the portion of the pool's value (after interest) that alice contributed.
        contributionWithInterest = uint256(poolValue2 - baseSpent).mulDown(
            aliceLpProportion
        );

        // calculate the portion of the fixed interest that alice earned
        fixedInterestEarned = baseSpent.mulDown(aliceLpProportion);

        // calculate the portion of the variable interest that alice owes
        variableInterestOwed = uint256(shortInterest).mulDown(
            aliceLpProportion
        );

        // calculate the portion of the fixed interest that alice owes
        fixedInterestOwed = totalFixedInterestOwed.mulDown(aliceLpProportion);

        // calculate the expected withdrawal proceeds
        expectedWithdrawalProceeds = calculateBaseLpProceeds(aliceLpShares);

        // Alice removes liquidity
        (withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e9);
    }

    function test_lp_fairness_long_short_lp(
        uint256 variableRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than or equal to 250%
        variableRateParam = variableRateParam.normalizeToRange(0, 2.5e18);

        // ensure a feasible trade size
        tradeSizeParam = tradeSizeParam.normalizeToRange(
            0.00001e18,
            5_000_000e18 - 0.000001e18
        );

        // variable interest rate earned by the pool
        int256 variableRate = int256(variableRateParam);

        uint256 aliceLpShares = 0;
        uint256 baseSpent = 0;
        uint256 poolValue = 0;
        uint256 bondsPurchased = 0;
        {
            // Initialize the pool with capital.
            uint256 initialLiquidity = 5_000_000e18;
            aliceLpShares = initialize(alice, 0.10e18, initialLiquidity);

            // Celine opens a long.
            baseSpent = 5_000_000e18 - tradeSizeParam;
            (, bondsPurchased) = openLong(celine, baseSpent);

            // 1/2 the term passes.
            advanceTime(POSITION_DURATION / 2, variableRate);
            (poolValue, ) = HyperdriveUtils.calculateCompoundInterest(
                initialLiquidity + baseSpent,
                variableRate,
                POSITION_DURATION / 2
            );
        }

        // Celine opens a short.
        uint256 bondsShorted = tradeSizeParam;
        (, uint256 baseSpent2) = openShort(celine, bondsShorted);

        uint256 bobLpShares = 0;
        uint256 poolValue2 = 0;

        {
            // Bob adds liquidity.
            uint256 contribution = 5_000_000e18;
            bobLpShares = addLiquidity(bob, contribution);

            // 1/2 the term passes.
            advanceTime(POSITION_DURATION / 2, variableRate);

            // Calculate the value of the pool after interest is accrued.
            (poolValue2, ) = HyperdriveUtils.calculateCompoundInterest(
                poolValue + contribution + baseSpent2,
                variableRate,
                POSITION_DURATION / 2
            );
        }
        // Calculate the total short interest.
        (, int256 shortInterest) = HyperdriveUtils.calculateCompoundInterest(
            bondsShorted,
            variableRate,
            POSITION_DURATION / 2
        );

        uint256 expectedWithdrawalProceeds = 0;
        {
            // calculate the portion of the pool's value (after interest) that bob contributed.
            uint256 contributionWithInterest = (poolValue2 -
                baseSpent2 -
                baseSpent).mulDivDown(
                    bobLpShares,
                    hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
                );

            // calculate the portion of the fixed interest that bob earned
            uint256 fixedInterestEarned = baseSpent2.mulDivDown(
                bobLpShares,
                hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
            );

            // calculate the portion of the variable interest that bob owes
            uint256 variableInterestOwed = uint256(shortInterest).mulDivDown(
                bobLpShares,
                hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
            );

            // calculate the portion of the fixed interest that bob owes
            uint256 fixedInterestOwed = (bondsPurchased - baseSpent).mulDivDown(
                bobLpShares,
                hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
            );

            // calculate the expected withdrawal shares base value so they can be removed from the expected proceeds
            uint256 withdrawalShareBaseValue = bondsShorted.mulDivDown(
                bobLpShares,
                hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
            );

            // calculate the expected withdrawal proceeds
            expectedWithdrawalProceeds =
                contributionWithInterest +
                fixedInterestEarned -
                variableInterestOwed -
                fixedInterestOwed -
                withdrawalShareBaseValue;
        }

        // calculate alice's proportion of LP shares
        uint256 aliceLpProportion = aliceLpShares.divDown(
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
        );
        {
            // Bob removes liquidity
            (uint256 bobWithdrawalProceeds, ) = removeLiquidity(
                bob,
                bobLpShares
            );
            assertApproxEqAbs(
                bobWithdrawalProceeds,
                expectedWithdrawalProceeds,
                1e9
            );
        }

        {
            // calculate the portion of the pool's value (after interest) that alice contributed.
            uint256 contributionWithInterest = (poolValue2 -
                baseSpent2 -
                baseSpent).mulDown(aliceLpProportion);

            // calculate the portion of the fixed interest that alice earned
            uint256 fixedInterestEarned = baseSpent2.mulDown(aliceLpProportion);

            // calculate the portion of the variable interest that alice owes
            uint256 variableInterestOwed = uint256(shortInterest).mulDown(
                aliceLpProportion
            );

            // calculate the portion of the fixed interest that alice owes
            uint256 fixedInterestOwed = (bondsPurchased - baseSpent).mulDown(
                aliceLpProportion
            );

            // calculate the expected withdrawal shares base value so they can be removed from the expected proceeds
            uint256 withdrawalShareBaseValue = bondsShorted.mulDown(
                aliceLpProportion
            );

            // calculate the expected withdrawal proceeds
            expectedWithdrawalProceeds =
                contributionWithInterest +
                fixedInterestEarned -
                variableInterestOwed -
                fixedInterestOwed -
                withdrawalShareBaseValue;
        }

        // Ensure that if the new LP withdraws, they get their money back.
        (uint256 aliceWithdrawalProceeds, ) = removeLiquidity(
            alice,
            aliceLpShares
        );
        assertApproxEqAbs(
            aliceWithdrawalProceeds,
            expectedWithdrawalProceeds,
            1e9
        );
    }
}
