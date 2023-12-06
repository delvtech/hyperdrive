// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract LPFairnessTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Deploy Hyperdrive with a small minimum share reserves so that it is
        // negligible relative to our error tolerances.
        IHyperdrive.PoolDeployConfig memory config = testConfig(0.05e18);
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
            MINIMUM_TRANSACTION_AMOUNT,
            5_000_000e18 - MINIMUM_TRANSACTION_AMOUNT
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
        (uint256 maturityTime, ) = openShort(celine, bondsShorted);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 bobLpShares = addLiquidity(bob, contribution);

        // The term passes.
        advanceTime(POSITION_DURATION, variableRate);

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = calculateBaseLpProceeds(
            bobLpShares
        );

        // Bob removes liquidity
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e4);

        // Celine closes her short.
        closeShort(celine, maturityTime, bondsShorted);

        // calculate the expected withdrawal proceeds
        expectedWithdrawalProceeds = calculateBaseLpProceeds(aliceLpShares);

        // Alice removes liquidity
        (withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e4);
    }

    function test_lp_fairness_short_short_lp(
        uint256 variableRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than or equal to 250%
        variableRateParam = variableRateParam.normalizeToRange(0, 2.5e18);

        // ensure a feasible trade size
        tradeSizeParam = tradeSizeParam.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            5_000_000e18 - MINIMUM_TRANSACTION_AMOUNT
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
        advanceTime(POSITION_DURATION / 2, variableRate);

        // Celine opens another short.
        uint256 bondsShorted2 = tradeSizeParam;
        openShort(celine, bondsShorted2);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 bobLpShares = addLiquidity(bob, contribution);

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, variableRate);

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = calculateBaseLpProceeds(
            bobLpShares
        );

        // Bob removes liquidity
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e4);

        // calculate the expected withdrawal proceeds
        expectedWithdrawalProceeds = calculateBaseLpProceeds(aliceLpShares);

        // Alice removes liquidity
        (withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e4);
    }

    function test_lp_fairness_long_lp(
        uint256 variableRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than or equal to 250%
        variableRateParam = variableRateParam.normalizeToRange(0, 2.5e18);

        // ensure a feasible trade size
        tradeSizeParam = tradeSizeParam.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            5_000_000e18 - MINIMUM_TRANSACTION_AMOUNT
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
        advanceTime(POSITION_DURATION, variableRate);

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = calculateBaseLpProceeds(
            bobLpShares
        );

        // Ensure that if the new LP withdraws, they get their money back.
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e4);

        // Celine closes her long.
        closeLong(celine, maturityTime, bondsPurchased);

        // calculate the expected withdrawal proceeds
        expectedWithdrawalProceeds = calculateBaseLpProceeds(aliceLpShares);

        // Alice removes liquidity
        (withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e4);
    }

    function test_lp_fairness_long_long_lp(
        uint256 variableRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than or equal to 250%
        variableRateParam = variableRateParam.normalizeToRange(0, 2.5e18);

        // ensure a feasible trade size
        tradeSizeParam = tradeSizeParam.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT * 2,
            5_000_000e18 - MINIMUM_TRANSACTION_AMOUNT
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
        advanceTime(POSITION_DURATION / 2, variableRate);

        // Celine opens another long.
        uint256 baseSpent2 = tradeSizeParam;
        openLong(celine, baseSpent2);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 bobLpShares = addLiquidity(bob, contribution);

        // 1/2 the term passes.
        advanceTime(POSITION_DURATION / 2, variableRate);

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = calculateBaseLpProceeds(
            bobLpShares
        );

        // Bob removes liquidity
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e4);

        // calculate alice's expected withdrawal proceeds
        expectedWithdrawalProceeds = calculateBaseLpProceeds(aliceLpShares);

        // Alice removes liquidity
        (withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e4);
    }

    function test_lp_fairness_short_long_lp(
        int256 variableRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than or equal to 250%
        variableRateParam = variableRateParam.normalizeToRange(0, 2.5e18);

        // ensure a feasible trade size
        tradeSizeParam = tradeSizeParam.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT * 2,
            5_000_000e18 - MINIMUM_TRANSACTION_AMOUNT
        );

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        uint256 aliceLpShares = initialize(alice, 0.1e18, initialLiquidity);

        // Celine opens a short.
        uint256 bondsShorted = 5_000_000e18 - tradeSizeParam;
        openShort(celine, bondsShorted);

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, variableRateParam);

        // Celine opens another long.
        openLong(celine, tradeSizeParam);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 bobLpShares = addLiquidity(bob, contribution);

        // 1/2 term passes.
        advanceTime(POSITION_DURATION / 2, variableRateParam);

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = calculateBaseLpProceeds(
            bobLpShares
        );

        // Bob removes liquidity
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e4);

        // calculate the expected withdrawal proceeds
        expectedWithdrawalProceeds = calculateBaseLpProceeds(aliceLpShares);

        // Alice removes liquidity
        (withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(withdrawalProceeds, expectedWithdrawalProceeds, 1e4);
    }

    function test_lp_fairness_long_short_lp(
        uint256 variableRateParam,
        uint256 tradeSizeParam
    ) external {
        // limit the fuzz testing to variableRate's less than or equal to 250%
        variableRateParam = variableRateParam.normalizeToRange(0, 2.5e18);

        // ensure a feasible trade size
        tradeSizeParam = tradeSizeParam.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            5_000_000e18 - MINIMUM_TRANSACTION_AMOUNT
        );

        // variable interest rate earned by the pool
        int256 variableRate = int256(variableRateParam);

        // Initialize the pool with capital.
        uint256 initialLiquidity = 5_000_000e18;
        uint256 aliceLpShares = initialize(alice, 0.10e18, initialLiquidity);

        // Celine opens a long.
        uint256 baseSpent = 5_000_000e18 - tradeSizeParam;
        openLong(celine, baseSpent);

        // 1/2 the term passes.
        advanceTime(POSITION_DURATION / 2, variableRate);

        // Celine opens a short.
        uint256 bondsShorted = tradeSizeParam;
        openShort(celine, bondsShorted);

        // Bob adds liquidity.
        uint256 contribution = 5_000_000e18;
        uint256 bobLpShares = addLiquidity(bob, contribution);

        // 1/2 the term passes.
        advanceTime(POSITION_DURATION / 2, variableRate);

        // calculate the expected withdrawal proceeds
        uint256 expectedWithdrawalProceeds = calculateBaseLpProceeds(
            bobLpShares
        );

        // Bob removes liquidity
        (uint256 bobWithdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(
            bobWithdrawalProceeds,
            expectedWithdrawalProceeds,
            1e4
        );

        // calculate the expected withdrawal proceeds
        expectedWithdrawalProceeds = calculateBaseLpProceeds(aliceLpShares);

        // Ensure that if the new LP withdraws, they get their money back.
        (uint256 aliceWithdrawalProceeds, ) = removeLiquidity(
            alice,
            aliceLpShares
        );
        assertApproxEqAbs(
            aliceWithdrawalProceeds,
            expectedWithdrawalProceeds,
            1e4
        );
    }
}
