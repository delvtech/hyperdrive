// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { MockHyperdriveMath } from "contracts/test/MockHyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

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
    using Lib for *;
    using HyperdriveUtils for IHyperdrive;

    uint256 fixedRate = 0.05e18;

    function setUp() public override {
        super.setUp();
        deploy(governance, fixedRate, 0.1e18, 0.1e18, 0.5e18, governance);

        uint256 initialLiquidity = 500_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);
    }

    struct LongScenario {
        uint256[4] fixedRates;
        uint256 celineBondAmount;
        uint256 celineBaseAmount;
        uint256 celineQuotedAPR;
        uint256 celineTimeRemaining;
        uint256 danBondAmount;
        uint256 danBaseAmount;
        uint256 danQuotedAPR;
        uint256 danTimeRemaining;
    }

    function test_fixed_rate_behaviour_long_interim_long_positive_interest_full_duration(
        uint256 _variableRate,
        uint256 baseAmount,
        uint256 interim,
        uint256 offset
    ) external {
        int256 variableRate = int256(_variableRate.normalizeToRange(0, 1e18));
        baseAmount = baseAmount.normalizeToRange(1000e18, 100_000_000e18);
        interim = interim.normalizeToRange(
            CHECKPOINT_DURATION,
            POSITION_DURATION * 25
        );
        offset = offset.normalizeToRange(0, CHECKPOINT_DURATION);

        LongScenario memory scenario = _scenarioLong(
            variableRate,
            baseAmount,
            interim,
            offset,
            false
        );

        assertEq(
            scenario.celineTimeRemaining,
            scenario.danTimeRemaining,
            "trades should be backdated equally"
        );
        assertGe(
            scenario.fixedRates[0],
            scenario.fixedRates[1],
            "fixed rate should decrease after celine opening and closing a long"
        );
        assertEq(
            scenario.fixedRates[1],
            scenario.fixedRates[2],
            "fixed rate should remain the same after accruing a long amount of interest"
        );
        assertGe(
            scenario.fixedRates[2],
            scenario.fixedRates[3],
            "fixed rate should decrease after dan opening and closing a long"
        );
        assertGt(
            scenario.celineBondAmount,
            scenario.danBondAmount,
            "Celine should get more bonds than dan"
        );

        // TODO Will fail for large interims
        // assertGt(
        //     scenario.celineBaseAmount,
        //     scenario.danBaseAmount,
        //     "Celine should receive marginally more base than Dan"
        // );
        // assertGt(
        //     scenario.celineQuotedAPR,
        //     scenario.danQuotedAPR,
        //     "Celine should be quoted a better fixed rate than Dan"
        // );
    }

    function test_fixed_rate_behaviour_long_interim_long_positive_interest_immediate_close(
        int256 variableRate,
        uint256 baseAmount,
        uint256 interim,
        uint256 offset
    ) external {
        variableRate = variableRate.normalizeToRange(0, 1e18);
        baseAmount = baseAmount.normalizeToRange(1000e18, 100_000_000e18);
        interim = interim.normalizeToRange(
            CHECKPOINT_DURATION,
            POSITION_DURATION * 25
        );
        offset = offset.normalizeToRange(0, CHECKPOINT_DURATION);

        LongScenario memory scenario = _scenarioLong(
            variableRate,
            baseAmount,
            interim,
            offset,
            true
        );

        assertEq(
            scenario.celineTimeRemaining,
            scenario.danTimeRemaining,
            "trades should be backdated equally"
        );
        assertGe(
            scenario.fixedRates[0],
            scenario.fixedRates[1],
            "fixed rate should decrease after celine opening and closing a long"
        );
        assertEq(
            scenario.fixedRates[1],
            scenario.fixedRates[2],
            "fixed rate should remain the same after accruing a long amount of interest"
        );
        assertGe(
            scenario.fixedRates[2],
            scenario.fixedRates[3],
            "fixed rate should decrease after dan opening and closing a long"
        );
        assertGt(
            scenario.celineBondAmount,
            scenario.danBondAmount,
            "Celine should get more bonds than dan"
        );

        // TODO Reconciling trade outcome behaviour on immediate close is hard
        // without extensive introspection on market conditions
        //
        // assertEq(
        //     scenario.celineBaseAmount,
        //     scenario.danBaseAmount,
        //     "Celine should receive marginally more base than Dan"
        // );
        // assertEq(
        //     scenario.celineQuotedAPR,
        //     scenario.danQuotedAPR,
        //     "Celine should be quoted a better fixed rate than Dan"
        // );
    }

    function test_fixed_rate_behaviour_long_interim_long_negative_interest_full_duration(
        uint256 _variableRate,
        uint256 baseAmount,
        uint256 interim,
        uint256 offset
    ) internal {
        int256 variableRate = -int256(
            _variableRate.normalizeToRange(0, 0.5e18)
        );
        baseAmount = baseAmount.normalizeToRange(1000e18, 100_000e18);
        interim = interim.normalizeToRange(
            CHECKPOINT_DURATION,
            POSITION_DURATION * 2
        );
        offset = offset.normalizeToRange(0, CHECKPOINT_DURATION);

        console2.log("variableRate: %s", variableRate.toString());
        console2.log("baseAmount: %s", baseAmount.toString());
        console2.log("interim: %s", interim.toString());
        console2.log("offset: %s", offset.toString());
        LongScenario memory scenario = _scenarioLong(
            variableRate,
            baseAmount,
            interim,
            offset,
            false
        );

        assertEq(
            scenario.celineTimeRemaining,
            scenario.danTimeRemaining,
            "trades should have equal amount of normalized time remaining"
        );
        assertGe(
            scenario.fixedRates[0],
            scenario.fixedRates[1],
            "fixed rate should decrease after celine opening and closing a long"
        );
        assertEq(
            scenario.fixedRates[1],
            scenario.fixedRates[2],
            "fixed rate should remain the same after accruing a long amount of interest"
        );
        assertGe(
            scenario.fixedRates[2],
            scenario.fixedRates[3],
            "fixed rate should decrease after dan opening and closing a long"
        );
        assertGt(
            scenario.celineBondAmount,
            scenario.danBondAmount,
            "Celine should get more bonds than dan"
        );
        assertGt(
            scenario.celineBaseAmount,
            scenario.danBaseAmount,
            "Celine should receive marginally more base than Dan"
        );
        assertGt(
            scenario.celineQuotedAPR,
            scenario.danQuotedAPR,
            "Celine should be quoted a better fixed rate than Dan"
        );
    }

    function test_negative_interest_full_duration_update_liquidity_revert()
        external
    {
        advanceTimeToNextCheckpoint(-0.000032446749640254e18);

        console2.log(
            "shareReserves: %s",
            hyperdrive.getPoolInfo().shareReserves.toString()
        );

        // Open and close a long
        (uint256 maturityTime, uint256 bondAmount) = openLong(celine, 1000e18);

        // int256 variableRate = -int256(_variableRate.normalizeToRange(0, 0.5e18));
        // baseAmount = baseAmount.normalizeToRange(1000e18, 100_000e18);
        // interim = interim.normalizeToRange(CHECKPOINT_DURATION, POSITION_DURATION * 2);
        // offset = offset.normalizeToRange(0, CHECKPOINT_DURATION);

        // LongScenario memory scenario = _scenarioLong(
        //     variableRate,
        //     baseAmount,
        //     interim,
        //     offset,
        //     false
        // );

        // assertEq(
        //     scenario.celineTimeRemaining,
        //     scenario.danTimeRemaining,
        //     "trades should have equal amount of normalized time remaining"
        // );
        // assertGe(
        //     scenario.fixedRates[0],
        //     scenario.fixedRates[1],
        //     "fixed rate should decrease after celine opening and closing a long"
        // );
        // assertEq(
        //     scenario.fixedRates[1],
        //     scenario.fixedRates[2],
        //     "fixed rate should remain the same after accruing a long amount of interest"
        // );
        // assertGe(
        //     scenario.fixedRates[2],
        //     scenario.fixedRates[3],
        //     "fixed rate should decrease after dan opening and closing a long"
        // );
        // assertGt(
        //     scenario.celineBondAmount,
        //     scenario.danBondAmount,
        //     "Celine should get more bonds than dan"
        // );
        // assertGt(
        //     scenario.celineBaseAmount,
        //     scenario.danBaseAmount,
        //     "Celine should receive marginally more base than Dan"
        // );
        // assertGt(
        //     scenario.celineQuotedAPR,
        //     scenario.danQuotedAPR,
        //     "Celine should be quoted a better fixed rate than Dan"
        // );
    }

    function _scenarioLong(
        int256 variableRate,
        uint256 baseAmount,
        uint256 interim,
        uint256 offset,
        bool immediateClose
    ) internal returns (LongScenario memory scenario) {
        // Cache the fixed rate
        scenario.fixedRates[0] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Advance to next checkpoint + offset
        advanceTimeToNextCheckpoint(variableRate, offset);

        // Open and close a long
        (uint256 maturityTime, uint256 bondAmount) = openLong(
            celine,
            baseAmount
        );
        scenario.celineBondAmount = bondAmount;
        scenario.celineQuotedAPR = HyperdriveUtils
            .calculateAPRFromRealizedPrice(
                baseAmount,
                bondAmount,
                FixedPointMath.ONE_18
            );
        scenario.celineTimeRemaining = hyperdrive.calculateTimeRemaining(
            maturityTime
        );
        if (!immediateClose) {
            advanceTime(maturityTime - block.timestamp, variableRate);
        }
        scenario.celineBaseAmount = closeLong(celine, maturityTime, bondAmount);

        // Cache the fixed rate
        scenario.fixedRates[1] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Advance to the nearest checkpoint interim seconds into the future
        // + offset seconds
        advanceTimeToNextCheckpoint(variableRate, offset);

        // Cache the fixed rate
        scenario.fixedRates[2] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long
        (maturityTime, bondAmount) = openLong(dan, baseAmount);
        scenario.danQuotedAPR = HyperdriveUtils.calculateAPRFromRealizedPrice(
            baseAmount,
            bondAmount,
            FixedPointMath.ONE_18
        );
        scenario.danTimeRemaining = hyperdrive.calculateTimeRemaining(
            maturityTime
        );
        if (!immediateClose) {
            advanceTime(maturityTime - block.timestamp, variableRate);
        }
        scenario.danBaseAmount = closeLong(dan, maturityTime, bondAmount);

        // Cache the fixed rate
        scenario.fixedRates[3] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
    }

    // function test_fixed_rate_behaviour_short_interim_short_positive_interest_full_duration()
    //     external
    // // uint64 _variableRate,
    // // uint96 _bondAmount,
    // // uint32 _interim,
    // // uint16 _offset
    // {
    //     // 5% < variableRate < 100%
    //     // 10000 < bondAmount < 450,000,000
    //     // 1 year <= interim <= 100 years
    //     //
    //     // vm.assume(_variableRate <= 0.95e18);
    //     // int256 variableRate = int256(uint256(_variableRate) + 0.05e18);
    //     // vm.assume(_bondAmount <= 450_000_000e18);
    //     // uint256 bondAmount = uint256(_bondAmount) + 10_000e18;
    //     // vm.assume(_interim <= (POSITION_DURATION * 100));
    //     // uint256 interim = uint256(_interim) + POSITION_DURATION;

    //     int256 variableRate = 0.1e18;
    //     uint256 bondAmount = 100_000e18;
    //     uint256 interim = (POSITION_DURATION * 5);

    //     // Initialize the pool with capital.
    //     uint256 initialLiquidity = 500_000_000e18;
    //     initialize(alice, fixedRate, initialLiquidity);

    //     // Advance time a duration so that an amount of interest has accrued
    //     advanceTime(1e8 + 12989889, variableRate);

    //     (
    //         uint256[4] memory spotFixedRates,
    //         ShortTrade memory celineShortTrade,
    //         ShortTrade memory danShortTrade
    //     ) = _scenarioShort(
    //             int256(uint256(variableRate)),
    //             bondAmount,
    //             interim,
    //             false
    //         );

    //     // assertEq(celineShortTrade.baseProceeds, danShortTrade.baseProceeds);

    //     // assertLt(
    //     //     spotFixedRates[0],
    //     //     spotFixedRates[1],
    //     //     "fixed rate should increase after celine opening and closing a short"
    //     // );
    //     // assertEq(
    //     //     spotFixedRates[1],
    //     //     spotFixedRates[2],
    //     //     "fixed rate should remain the same after accruing a long amount of interest"
    //     // );
    //     // assertLt(
    //     //     spotFixedRates[2],
    //     //     spotFixedRates[3],
    //     //     "fixed rate should increase after dan opening and closing a short"
    //     // );

    //     // A short is a promise to purchase at a future point in time

    //     // TODO Discern conditions which would incur this to be higher or lower
    //     // assertGt(
    //     //     scenario.celineShortInterestEarned,
    //     //     scenario.danShortInterestEarned,
    //     //     "interest earned on shorts should be the same"
    //     // );

    //     // // TODO Discern conditions which would incur this to be higher or lower
    //     // assertLt(
    //     //     scenario.celineQuotedAPR,
    //     //     scenario.danQuotedAPR,
    //     //     "The first quote should imply a better fixed rate than the second"
    //     // );
    // }

    // function _scenarioShort(
    //     int256 variableRate,
    //     uint256 bondAmount,
    //     uint256 interim,
    //     bool immediateClose
    // )
    //     internal
    //     returns (
    //         uint256[4] memory spotFixedRates,
    //         ShortTrade memory celineShortTrade,
    //         ShortTrade memory danShortTrade
    //     )
    // {
    //     spotFixedRates[0] = HyperdriveUtils.calculateAPRFromReserves(
    //         hyperdrive
    //     );

    //     _makeShortTrade(
    //         celineShortTrade,
    //         variableRate,
    //         bondAmount,
    //         immediateClose
    //     );

    //     spotFixedRates[1] = HyperdriveUtils.calculateAPRFromReserves(
    //         hyperdrive
    //     );
    //     advanceTime(interim, variableRate);
    //     spotFixedRates[2] = HyperdriveUtils.calculateAPRFromReserves(
    //         hyperdrive
    //     );

    //     _makeShortTrade(
    //         danShortTrade,
    //         variableRate,
    //         bondAmount,
    //         immediateClose
    //     );

    //     spotFixedRates[3] = HyperdriveUtils.calculateAPRFromReserves(
    //         hyperdrive
    //     );

    //     /// LOGGING ///

    //     console2.log("\tfixedRate 1:\t\t%s", (spotFixedRates[0]).toPercent());
    //     console2.log("\tfixedRate 2:\t\t%s", (spotFixedRates[1]).toPercent());
    //     console2.log("\tfixedRate 3:\t\t%s", (spotFixedRates[2]).toPercent());
    //     console2.log("\tfixedRate 4:\t\t%s", (spotFixedRates[3]).toPercent());
    // }

    // function _makeShortTrade(
    //     ShortTrade memory _trade,
    //     int256 variableRate,
    //     uint256 bondAmount,
    //     bool immediateClose
    // ) internal {
    //     _trade.openSharePrice = hyperdrive.getPoolInfo().sharePrice;
    //     _trade.openBondPrice = hyperdrive.bondPrice(FixedPointMath.ONE_18);
    //     _trade.bondAmount = bondAmount;
    //     // Open and close a short
    //     (uint256 maturityTime, uint256 basePaid) = openShort(
    //         celine,
    //         bondAmount
    //     );
    //     _trade.basePaid = basePaid;
    //     _trade.quotedAPR = HyperdriveUtils.calculateAPRFromRealizedPrice(
    //         bondAmount - basePaid,
    //         bondAmount,
    //         FixedPointMath.ONE_18
    //     );
    //     _trade.secondsBackdated =
    //         block.timestamp -
    //         hyperdrive.latestCheckpoint();
    //     if (!immediateClose) {
    //         advanceTime(POSITION_DURATION, variableRate);
    //     }
    //     _trade.closeBondPrice = hyperdrive.bondPrice(
    //         hyperdrive.calculateTimeRemaining(maturityTime)
    //     );
    //     _trade.closeSharePrice = hyperdrive.getPoolInfo().sharePrice;
    //     _trade.interestEarned = hyperdriveMath.calculateShortInterest(
    //         bondAmount,
    //         _trade.openSharePrice,
    //         _trade.closeSharePrice,
    //         _trade.closeSharePrice
    //     );
    //     _trade.baseProceeds = closeShort(celine, maturityTime, bondAmount);
    // }
}
