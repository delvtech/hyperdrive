// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

contract SingleLong is HyperdriveTest {
    using FixedPointMath for uint256;

    uint256 public fee = 0.01e18;
    uint256 public targetAPR = 0.05e18;

    function setUp() public override {
        super.setUp();

        // Deploy and initialize a new pool with fees.
        deploy(alice, targetAPR, fee, fee, 0.5e18, governance);
        initialize(alice, targetAPR, 500_000_000e18);
    }

    function test_trade_single_long_full_duration_small_trade() external {
        // small base amount
        uint256 baseAmount = 1_000e18;

        // Make the trade
        (uint256 maturity, uint256 bondAmount, uint256 baseProceeds) = _trade(
            baseAmount,
            POSITION_DURATION
        );

        // Fixed rate is expected to have decreased ~0.000256% after opening a
        // long
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[0], fixedRateCache[1]),
            -0.00000256e18,
            0.00000001e18
        );

        // Fixed rate is expected to not change after closing a fully-matured
        // long
        assertEq(calculatePriceImpact(fixedRateCache[1], fixedRateCache[2]), 0);

        // Profits
        int256 profits = int256(baseProceeds) - int256(baseAmount);
        int256 expectedProfits = estimateBondProfits(
            bondAmount,
            baseAmount,
            maturity
        );
        assertApproxEqAbs(profits, expectedProfits, 2);
    }

    function test_trade_single_long_full_duration_medium_trade() external {
        // medium base amount
        uint256 baseAmount = 1_000_000e18;

        // Make the trade
        (uint256 maturity, uint256 bondAmount, uint256 baseProceeds) = _trade(
            baseAmount,
            POSITION_DURATION
        );

        // Fixed rate is expected to have decreased ~0.256%
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[0], fixedRateCache[1]),
            -0.00256e18,
            0.00001e18
        );

        // Fixed rate is expected to not change after closing a fully-matured
        // long
        assertEq(calculatePriceImpact(fixedRateCache[1], fixedRateCache[2]), 0);

        // Profits
        int256 profits = int256(baseProceeds) - int256(baseAmount);
        int256 expectedProfits = estimateBondProfits(
            bondAmount,
            baseAmount,
            maturity
        );
        assertApproxEqAbs(profits, expectedProfits, 2);
    }

    function test_trade_single_long_full_duration_large_trade() external {
        // large base amount
        uint256 baseAmount = 100_000_000e18;

        // Make the trade
        (uint256 maturity, uint256 bondAmount, uint256 baseProceeds) = _trade(
            baseAmount,
            POSITION_DURATION
        );

        // Fixed rate is expected to have decreased ~24.05%
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[0], fixedRateCache[1]),
            -0.2405e18,
            0.00005e18
        );

        // Fixed rate is expected to not change after closing a fully-matured
        // long
        assertEq(calculatePriceImpact(fixedRateCache[1], fixedRateCache[2]), 0);

        // Profits
        int256 profits = int256(baseProceeds) - int256(baseAmount);
        int256 expectedProfits = estimateBondProfits(
            bondAmount,
            baseAmount,
            maturity
        );
        assertApproxEqAbs(profits, expectedProfits, 1);
    }

    function test_trade_single_long_half_duration_small_trade() external {
        // small base amount
        uint256 baseAmount = 1_000e18;

        // Make the trade
        (uint256 maturity, uint256 bondAmount, uint256 baseProceeds) = _trade(
            baseAmount,
            POSITION_DURATION / 2
        );

        // Fixed rate is expected to have decreased ~0.000256% after opening a
        // long
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[0], fixedRateCache[1]),
            -0.00000256e18,
            0.00000001e18
        );

        // Fixed rate is expected to have increased ~0.0001258% after closing
        // the long
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[1], fixedRateCache[2]),
            0.000001258e18,
            0.000000001e18
        );

        // Profits
        int256 profits = int256(baseProceeds - baseAmount);
        int256 expectedProfits = estimateBondProfits(
            bondAmount,
            baseAmount,
            maturity
        );
        assertApproxEqAbs(profits, expectedProfits, 0.15e18);
    }

    function test_trade_single_long_half_duration_medium_trade() external {
        // medium base amount
        uint256 baseAmount = 1_000_000e18;

        // Make the trade
        (uint256 maturity, uint256 bondAmount, uint256 baseProceeds) = _trade(
            baseAmount,
            POSITION_DURATION / 2
        );

        // Fixed rate is expected to have decreased ~0.256%
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[0], fixedRateCache[1]),
            -0.00256e18,
            0.00001e18
        );

        // Fixed rate is expected to have increased ~0.1258% after closing
        // the long
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[1], fixedRateCache[2]),
            0.001258e18,
            0.000003e18
        );

        // Profits
        int256 profits = int256(baseProceeds) - int256(baseAmount);
        int256 expectedProfits = estimateBondProfits(
            bondAmount,
            baseAmount,
            maturity
        );
        assertApproxEqAbs(profits, expectedProfits, 120e18);
    }

    function test_trade_single_long_half_duration_large_trade() external {
        // large base amount
        uint256 baseAmount = 100_000_000e18;

        // Make the trade
        (uint256 maturity, uint256 bondAmount, uint256 baseProceeds) = _trade(
            baseAmount,
            POSITION_DURATION / 2
        );

        // Fixed rate is expected to have decreased ~24.05%
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[0], fixedRateCache[1]),
            -0.2405e18,
            0.00005e18
        );

        // Fixed rate is expected to have increased ~15.1% after closing
        // the long
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[1], fixedRateCache[2]),
            0.151e18,
            0.0001e18
        );

        // Profits
        int256 profits = int256(baseProceeds) - int256(baseAmount);
        int256 expectedProfits = estimateBondProfits(
            bondAmount,
            baseAmount,
            maturity
        );
        // TODO - Huge error bar, needs refinement
        assertApproxEqAbs(profits, expectedProfits, 130_000e18);
    }

    function test_trade_single_long_0_duration_small_trade() external {
        // small base amount
        uint256 baseAmount = 1_000e18;

        // Make the trade
        (uint256 maturity, uint256 bondAmount, uint256 baseProceeds) = _trade(
            baseAmount,
            0
        );

        // Fixed rate is expected to have decreased ~0.000256% after opening a
        // long
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[0], fixedRateCache[1]),
            -0.00000256e18,
            0.00000001e18
        );

        // Fixed rate is expected to have increased ~0.000256% after closing
        // the long
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[1], fixedRateCache[2]),
            0.00000256e18,
            0.00000001e18
        );

        int256 priceImpact = calculatePriceImpact(
            fixedRateCache[0],
            fixedRateCache[2]
        );

        console2.log("priceImpact", priceImpact);
        console2.log(
            "bb",
            baseAmount.sub(baseAmount.mulDown(uint256(-priceImpact)))
        );
        // Fixed rate is expected to barely deviate from original price
        assertApproxEqAbs(priceImpact, -0.0000000015e18, 0.00000000005e18);

        // Profits
        int256 profits = int256(baseProceeds) - int256(baseAmount);
        int256 expectedProfits = estimateBondProfits(
            bondAmount,
            baseAmount,
            maturity
        );
        assertApproxEqAbs(profits, expectedProfits, 1);
    }

    function test_trade_single_long_0_duration_medium_trade() external {
        // medium base amount
        uint256 baseAmount = 1_000_000e18;

        // Make the trade
        (, , uint256 baseProceeds) = _trade(baseAmount, 0);

        // Fixed rate is expected to have decreased ~0.256%
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[0], fixedRateCache[1]),
            -0.00256e18,
            0.00001e18
        );

        // Fixed rate is expected to have increased ~0.256% after closing
        // the long
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[1], fixedRateCache[2]),
            0.00256e18,
            0.00001e18
        );

        // Fixed rate is expected to barely deviate from original price
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[0], fixedRateCache[2]),
            -0.0000015e18,
            0.00000005e18
        );

        // Profits
        int256 profits = int256(baseProceeds) - int256(baseAmount);
        assertApproxEqAbs(profits, -1_000e18, 30e18);
    }

    function test_trade_single_long_0_duration_large_trade() external {
        // large base amount
        uint256 baseAmount = 100_000_000e18;

        // Make the trade
        (, , uint256 baseProceeds) = _trade(baseAmount, 0);

        // Fixed rate is expected to have decreased ~24.05%
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[0], fixedRateCache[1]),
            -0.2405e18,
            0.00005e18
        );

        // Fixed rate is expected to have increased ~31.65% after closing
        // the long
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[1], fixedRateCache[2]),
            0.3165e18,
            0.0001e18
        );

        // Fixed rate is expected to barely deviate from original price
        assertApproxEqAbs(
            calculatePriceImpact(fixedRateCache[0], fixedRateCache[2]),
            -0.00014e18,
            0.000005e18
        );

        // Profits
        int256 profits = int256(baseProceeds) - int256(baseAmount);
        assertApproxEqAbs(profits, -86_000e18, 100e18);
    }

    function _trade(
        uint256 baseAmount,
        uint256 duration
    )
        private
        returns (uint256 maturity, uint256 bondAmount, uint256 baseProceeds)
    {
        cacheFixedRate();

        // Open a long
        (maturity, bondAmount) = openLong(bob, baseAmount);

        cacheFixedRate();

        // Advance time
        advanceTime(duration, int256(targetAPR));

        // Close the long
        baseProceeds = closeLong(bob, maturity, bondAmount);

        cacheFixedRate();
    }
}
