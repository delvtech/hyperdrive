// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";

// TODO Cases
// [] - long - interim - long - positive APR - full duration trades
// [] - long - interim - long - positive APR - immediate close trades
// [] - long - interim - long - negative APR - full duration trades
// [] - long - interim - long - negative APR - immediate close trades
//
// [] - short - interim - short - positive APR - full duration trades
// [] - short - interim - short - positive APR - immediate close trades
// [] - short - interim - short - negative APR - full duration trades
// [] - short - interim - short - negative APR - immediate close trades
//
contract FixedRateBehaviour is HyperdriveTest {
    using FixedPointMath for uint256;

    // TODO Experimentation with increasingly larger and more pathological
    // interims and variable rates eventually resulted in several scenarios
    // where either mathematical overflows and NegativeInterest errors occured.
    // Typically this was a result of sharePrice being exorbitantly high
    //
    // FAIL: [850158846099921994, 3555210678590931723272, 664330425]
    //   Breaks the assumption that 1st trade should be a better outcome than 2nd
    function test_fixed_rate_behaviour_long_interim_long_positive_interest_full_duration(
        uint64 _variableRate,
        uint256 baseAmount,
        uint32 interim
    ) external {
        // 0% < variableRate < 100%
        // 1000 < baseAmount < 100,000,000
        // interim <= 25 years
        int256 variableRate = int256(uint256(_variableRate) % 1e18);
        vm.assume(baseAmount >= 1000e18 && baseAmount <= 100_000_000e18);
        vm.assume(interim <= POSITION_DURATION * 25);

        // Initialize the pool with capital.
        uint256 fixedRate = 0.05e18;
        uint256 initialLiquidity = 500_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);

        // Advance time a duration so that an amount of interest has accrued
        advanceTime(POSITION_DURATION, variableRate);

        (
            uint256[4] memory spotFixedRates,
            ,
            uint256 celineBaseAmount,
            uint256 celineQuotedAPR,
            ,
            uint256 danBaseAmount,
            uint256 danQuotedAPR
        ) = _scenarioLong(variableRate, baseAmount, interim, false);

        assertGe(
            spotFixedRates[0],
            spotFixedRates[1],
            "fixed rate should decrease after celine opening and closing a long"
        );
        assertEq(
            spotFixedRates[1],
            spotFixedRates[2],
            "fixed rate should remain the same after accruing a long amount of interest"
        );
        assertGe(
            spotFixedRates[2],
            spotFixedRates[3],
            "fixed rate should decrease after dan opening and closing a long"
        );
        assertGt(
            celineBaseAmount,
            danBaseAmount,
            "The first long trade should return marginally more than the second"
        );
        assertGt(
            celineQuotedAPR,
            danQuotedAPR,
            "The first long should imply a better fixed rate than the second"
        );
    }

    //
    // FAIL: [850158846099921994, 3555210678590931723272, 664330425]
    //
    // spotFixedRate0: 49999999999999999
    // spotFixedRate1: 49999818857189771
    // spotFixedRate2: 49999818857189771
    // spotFixedRate3: 49999699170919011
    // Error: The first long trade should return marginally more than the second
    // Error: a > b not satisfied [uint]
    //   Value a: 3732970890516026173847
    //   Value b: 3732970923046814250303
    // Error: The first long should imply a better fixed rate than the second
    // Error: a > b not satisfied [uint]
    //   Value a: 49999909427462604
    //   Value b: 49999918577915528
    function test_fixed_rate_behaviour_breaking_case() external {
        int256 variableRate = 850158846099921994; // ~ 85%
        uint256 baseAmount = 3555210678590931723272; // ~3555.21
        uint32 interim = 664330425; // ~21 years

        // Initialize the pool with capital.
        uint256 fixedRate = 0.05e18;
        uint256 initialLiquidity = 500_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);

        // Advance time a duration so that an amount of interest has accrued
        advanceTime(POSITION_DURATION, variableRate);

        (
            uint256[4] memory spotFixedRates,
            ,
            uint256 celineBaseAmount,
            uint256 celineQuotedAPR,
            ,
            uint256 danBaseAmount,
            uint256 danQuotedAPR
        ) = _scenarioLong(variableRate, baseAmount, interim, false);

        assertGe(
            spotFixedRates[0],
            spotFixedRates[1],
            "fixed rate should decrease after celine opening and closing a long"
        );
        assertEq(
            spotFixedRates[1],
            spotFixedRates[2],
            "fixed rate should remain the same after accruing a long amount of interest"
        );
        assertGe(
            spotFixedRates[2],
            spotFixedRates[3],
            "fixed rate should decrease after dan opening and closing a long"
        );

        console2.log("spotFixedRate0: %s", spotFixedRates[0]);
        console2.log("spotFixedRate1: %s", spotFixedRates[1]);
        console2.log("spotFixedRate2: %s", spotFixedRates[2]);
        console2.log("spotFixedRate3: %s", spotFixedRates[3]);

        assertGt(
            celineBaseAmount,
            danBaseAmount,
            "The first long trade should return marginally more than the second"
        );
        assertGt(
            celineQuotedAPR,
            danQuotedAPR,
            "The first long should imply a better fixed rate than the second"
        );
    }

    function _scenarioLong(
        int256 variableRate,
        uint256 baseAmount,
        uint256 interim,
        bool immediateClose
    )
        internal
        returns (
            uint256[4] memory spotFixedRates,
            uint256 celineBondAmount,
            uint256 celineBaseAmount,
            uint256 celineQuotedAPR,
            uint256 danBondAmount,
            uint256 danBaseAmount,
            uint256 danQuotedAPR
        )
    {
        // Advance time using the baseAmount so that an arbitrary amount of
        // interest has accrued
        advanceTime(POSITION_DURATION, variableRate);

        spotFixedRates[0] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long
        uint256 celineMaturityTime;
        (celineMaturityTime, celineBondAmount) = openLong(celine, baseAmount);
        celineQuotedAPR = HyperdriveUtils.calculateAPRFromRealizedPrice(
            baseAmount,
            celineBondAmount,
            FixedPointMath.ONE_18
        );
        if (!immediateClose) {
            advanceTime(celineMaturityTime - block.timestamp, variableRate);
        }
        celineBaseAmount = closeLong(
            celine,
            celineMaturityTime,
            celineBondAmount
        );

        spotFixedRates[1] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Advance the interim amount of time accruing variable rate
        advanceTime(interim, variableRate);

        spotFixedRates[2] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long
        uint256 danMaturityTime;
        (danMaturityTime, danBondAmount) = openLong(dan, baseAmount);
        danQuotedAPR = HyperdriveUtils.calculateAPRFromRealizedPrice(
            baseAmount,
            danBondAmount,
            FixedPointMath.ONE_18
        );
        if (!immediateClose) {
            advanceTime(danMaturityTime - block.timestamp, variableRate);
        }
        danBaseAmount = closeLong(dan, danMaturityTime, danBondAmount);

        spotFixedRates[3] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
    }

    // function test_fixed_rate_behaviour_long_interim_long_positive_interest_immediate_closing(
    //     uint64 _variableRate,
    //     uint256 baseAmount,
    //     uint32 interim
    // ) external {
    //     uint256 fixedRate = 0.05e18;

    //     // 0% < variableRate < 100%
    //     int256 variableRate = int256(uint256(_variableRate) % 1e18);

    //     // 1000 < baseAmount < 100,000,000
    //     vm.assume(baseAmount >= 1000e18 && baseAmount <= 100_000_000e18);

    //     // interim <= 50 years
    //     vm.assume(interim <= POSITION_DURATION * 25);

    //     // Initialize the pool with capital.
    //     uint256 initialLiquidity = 500_000_000e18;
    //     initialize(alice, fixedRate, initialLiquidity);

    //     // Advance time using the baseAmount so that an arbitrary amount of
    //     // interest has accrued
    //     advanceTime(POSITION_DURATION, variableRate);

    //     spotFixedRate1 = HyperdriveUtils.calculateAPRFromReserves(
    //         hyperdrive
    //     );

    //     // Open and close a long so that system accounting is cycled
    //     (uint256 celineMaturityTime, uint256 celineBondAmount) = openLong(
    //         celine,
    //         baseAmount
    //     );
    //     uint256 celineBaseAmount = closeLong(
    //         celine,
    //         celineMaturityTime,
    //         celineBondAmount
    //     );

    //     spotFixedRate2 = HyperdriveUtils.calculateAPRFromReserves(
    //         hyperdrive
    //     );

    //     // Advance the interim amount of time accruing variable rate
    //     advanceTime(uint256(interim), variableRate);

    //     spotFixedRate3 = HyperdriveUtils.calculateAPRFromReserves(
    //         hyperdrive
    //     );

    //     // Open and close a long
    //     (uint256 danMaturityTime, uint256 danBondAmount) = openLong(
    //         dan,
    //         baseAmount
    //     );
    //     uint256 danBaseAmount = closeLong(dan, danMaturityTime, danBondAmount);

    //     spotFixedRate4 = HyperdriveUtils.calculateAPRFromReserves(
    //         hyperdrive
    //     );

    //     assertGe(
    //         spotFixedRate1,
    //         spotFixedRate2,
    //         "fixed rate should decrease after celine opening and closing a long"
    //     );
    //     assertEq(
    //         spotFixedRate2,
    //         spotFixedRate3,
    //         "fixed rate should remain the same after accruing a long amount of interest"
    //     );
    //     assertGe(
    //         spotFixedRate3,
    //         spotFixedRate4,
    //         "fixed rate should decrease after dan opening and closing a long"
    //     );
    // }

    // // [-731931430838270598, 69000408175263547825293173, 0] Evm revert
    // function test_fixed_rate_behaviour_long_interim_long_negative_interest(
    //     int64 variableRate,
    //     uint256 baseAmount,
    //     uint32 interim
    // ) external {
    //     uint256 fixedRate = 0.05e18;

    //     // 0% < variableRate < -100%
    //     vm.assume(variableRate < 0 && variableRate >= -1e18);

    //     // 1000 < baseAmount < 100,000,000
    //     vm.assume(baseAmount >= 1000e18 && baseAmount <= 100_000_000e18);

    //     // interim <= 50 years
    //     vm.assume(interim <= POSITION_DURATION);

    //     // Initialize the pool with capital.
    //     uint256 initialLiquidity = 500_000_000e18;
    //     initialize(alice, fixedRate, initialLiquidity);

    //     // Advance time using the baseAmount so that an arbitrary amount of
    //     // interest has accrued
    //     advanceTime(POSITION_DURATION, variableRate);

    //     spotFixedRate1 = HyperdriveUtils.calculateAPRFromReserves(
    //         hyperdrive
    //     );

    //     // Open and close a long so that system accounting is cycled
    //     (uint256 celineMaturityTime, uint256 celineBondAmount) = openLong(
    //         celine,
    //         baseAmount
    //     );
    //     advanceTime(celineMaturityTime - block.timestamp, variableRate);
    //     uint256 celineBaseAmount = closeLong(
    //         celine,
    //         celineMaturityTime,
    //         celineBondAmount
    //     );

    //     spotFixedRate2 = HyperdriveUtils.calculateAPRFromReserves(
    //         hyperdrive
    //     );

    //     // Advance the interim amount of time accruing variable rate
    //     advanceTime(uint256(interim), variableRate);

    //     spotFixedRate3 = HyperdriveUtils.calculateAPRFromReserves(
    //         hyperdrive
    //     );

    //     // Open and close a long
    //     (uint256 danMaturityTime, uint256 danBondAmount) = openLong(
    //         dan,
    //         baseAmount
    //     );
    //     advanceTime(danMaturityTime - block.timestamp, variableRate);
    //     uint256 danBaseAmount = closeLong(dan, danMaturityTime, danBondAmount);

    //     spotFixedRate4 = HyperdriveUtils.calculateAPRFromReserves(
    //         hyperdrive
    //     );

    //     assertGe(
    //         spotFixedRate1,
    //         spotFixedRate2,
    //         "fixed rate should decrease after celine opening and closing a long"
    //     );
    //     assertEq(
    //         spotFixedRate2,
    //         spotFixedRate3,
    //         "fixed rate should remain the same after accruing a long amount of interest"
    //     );
    //     assertGe(
    //         spotFixedRate3,
    //         spotFixedRate4,
    //         "fixed rate should decrease after dan opening and closing a long"
    //     );
    // }
}
