// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";

contract FixedRateBehaviour is HyperdriveTest {
    using FixedPointMath for uint256;

    uint256 spotFixedRate1;
    uint256 spotFixedRate2;
    uint256 spotFixedRate3;
    uint256 spotFixedRate4;

    // TODO Can fail if variable interest is large enough and interim is long enough
    // such that the sharePrice becomes very large
    function test_fixed_rate_behaviour_long_interim_long_positive_interest(
        uint64 _variableRate,
        uint256 baseAmount,
        uint32 interim
    ) external {
        uint256 fixedRate = 0.05e18;

        // 0% < variableRate < 100%
        int256 variableRate = int256(uint256(_variableRate) % 1e18);

        // 1000 < baseAmount < 100,000,000
        vm.assume(baseAmount >= 1000e18 && baseAmount <= 100_000_000e18);

        // interim <= 50 years
        vm.assume(interim <= POSITION_DURATION * 25);

        // Initialize the pool with capital.
        uint256 initialLiquidity = 500_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);

        // Advance time using the baseAmount so that an arbitrary amount of
        // interest has accrued
        advanceTime(POSITION_DURATION, variableRate);

        spotFixedRate1 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long so that system accounting is cycled
        (uint256 celineMaturityTime, uint256 celineBondAmount) = openLong(
            celine,
            baseAmount
        );
        advanceTime(celineMaturityTime - block.timestamp, variableRate);
        uint256 celineBaseAmount = closeLong(
            celine,
            celineMaturityTime,
            celineBondAmount
        );

        spotFixedRate2 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Advance the interim amount of time accruing variable rate
        advanceTime(uint256(interim), variableRate);

        spotFixedRate3 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long
        (uint256 danMaturityTime, uint256 danBondAmount) = openLong(
            dan,
            baseAmount
        );
        advanceTime(danMaturityTime - block.timestamp, variableRate);
        uint256 danBaseAmount = closeLong(dan, danMaturityTime, danBondAmount);

        spotFixedRate4 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        assertGe(
            spotFixedRate1,
            spotFixedRate2,
            "fixed rate should decrease after celine opening and closing a long"
        );
        assertEq(
            spotFixedRate2,
            spotFixedRate3,
            "fixed rate should remain the same after accruing a long amount of interest"
        );
        assertGe(
            spotFixedRate3,
            spotFixedRate4,
            "fixed rate should decrease after dan opening and closing a long"
        );
    }


    function test_fixed_rate_behaviour_long_interim_long_positive_interest_immediate_closing(
        uint64 _variableRate,
        uint256 baseAmount,
        uint32 interim
    ) external {
        uint256 fixedRate = 0.05e18;

        // 0% < variableRate < 100%
        int256 variableRate = int256(uint256(_variableRate) % 1e18);

        // 1000 < baseAmount < 100,000,000
        vm.assume(baseAmount >= 1000e18 && baseAmount <= 100_000_000e18);

        // interim <= 50 years
        vm.assume(interim <= POSITION_DURATION * 25);

        // Initialize the pool with capital.
        uint256 initialLiquidity = 500_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);

        // Advance time using the baseAmount so that an arbitrary amount of
        // interest has accrued
        advanceTime(POSITION_DURATION, variableRate);

        spotFixedRate1 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long so that system accounting is cycled
        (uint256 celineMaturityTime, uint256 celineBondAmount) = openLong(
            celine,
            baseAmount
        );
        uint256 celineBaseAmount = closeLong(
            celine,
            celineMaturityTime,
            celineBondAmount
        );

        spotFixedRate2 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Advance the interim amount of time accruing variable rate
        advanceTime(uint256(interim), variableRate);

        spotFixedRate3 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long
        (uint256 danMaturityTime, uint256 danBondAmount) = openLong(
            dan,
            baseAmount
        );
        uint256 danBaseAmount = closeLong(dan, danMaturityTime, danBondAmount);

        spotFixedRate4 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        assertGe(
            spotFixedRate1,
            spotFixedRate2,
            "fixed rate should decrease after celine opening and closing a long"
        );
        assertEq(
            spotFixedRate2,
            spotFixedRate3,
            "fixed rate should remain the same after accruing a long amount of interest"
        );
        assertGe(
            spotFixedRate3,
            spotFixedRate4,
            "fixed rate should decrease after dan opening and closing a long"
        );
    }

    // [-731931430838270598, 69000408175263547825293173, 0] Evm revert
    function test_fixed_rate_behaviour_long_interim_long_negative_interest(
        int64 variableRate,
        uint256 baseAmount,
        uint32 interim
    ) external {
        uint256 fixedRate = 0.05e18;

        // 0% < variableRate < -100%
        vm.assume(variableRate < 0 && variableRate >= -1e18);

        // 1000 < baseAmount < 100,000,000
        vm.assume(baseAmount >= 1000e18 && baseAmount <= 100_000_000e18);

        // interim <= 50 years
        vm.assume(interim <= POSITION_DURATION);

        // Initialize the pool with capital.
        uint256 initialLiquidity = 500_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);

        // Advance time using the baseAmount so that an arbitrary amount of
        // interest has accrued
        advanceTime(POSITION_DURATION, variableRate);

        spotFixedRate1 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long so that system accounting is cycled
        (uint256 celineMaturityTime, uint256 celineBondAmount) = openLong(
            celine,
            baseAmount
        );
        advanceTime(celineMaturityTime - block.timestamp, variableRate);
        uint256 celineBaseAmount = closeLong(
            celine,
            celineMaturityTime,
            celineBondAmount
        );

        spotFixedRate2 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Advance the interim amount of time accruing variable rate
        advanceTime(uint256(interim), variableRate);

        spotFixedRate3 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long
        (uint256 danMaturityTime, uint256 danBondAmount) = openLong(
            dan,
            baseAmount
        );
        advanceTime(danMaturityTime - block.timestamp, variableRate);
        uint256 danBaseAmount = closeLong(dan, danMaturityTime, danBondAmount);

        spotFixedRate4 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        assertGe(
            spotFixedRate1,
            spotFixedRate2,
            "fixed rate should decrease after celine opening and closing a long"
        );
        assertEq(
            spotFixedRate2,
            spotFixedRate3,
            "fixed rate should remain the same after accruing a long amount of interest"
        );
        assertGe(
            spotFixedRate3,
            spotFixedRate4,
            "fixed rate should decrease after dan opening and closing a long"
        );
    }
}
