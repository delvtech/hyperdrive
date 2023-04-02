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
    }

    // Used to calculate short interest
    MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

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

    struct ShortTrade {
        uint256 quotedAPR;
        uint256 bondAmount;
        uint256 interestEarned;
        uint256 openSharePrice;
        uint256 openBondPrice;
        uint256 closeSharePrice;
        uint256 closeBondPrice;
        uint256 baseProceeds;
        uint256 basePaid;
        uint256 secondsBackdated;
    }

    function test_fixed_rate_behaviour_short_interim_short_positive_interest_full_duration()
        external
    // uint64 _variableRate,
    // uint96 _bondAmount,
    // uint32 _interim,
    // uint16 _offset
    {
        // 5% < variableRate < 100%
        // 10000 < bondAmount < 450,000,000
        // 1 year <= interim <= 100 years
        //
        // vm.assume(_variableRate <= 0.95e18);
        // int256 variableRate = int256(uint256(_variableRate) + 0.05e18);
        // vm.assume(_bondAmount <= 450_000_000e18);
        // uint256 bondAmount = uint256(_bondAmount) + 10_000e18;
        // vm.assume(_interim <= (POSITION_DURATION * 100));
        // uint256 interim = uint256(_interim) + POSITION_DURATION;

        int256 variableRate = 0.1e18;
        uint256 bondAmount = 100_000e18;
        uint256 interim = (POSITION_DURATION * 5);

        // Initialize the pool with capital.
        uint256 initialLiquidity = 500_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);

        // Advance time a duration so that an amount of interest has accrued
        advanceTime(1e8 + 12989889, variableRate);

        (
            uint256[4] memory spotFixedRates,
            ShortTrade memory celineShortTrade,
            ShortTrade memory danShortTrade
        ) = _scenarioShort(
                int256(uint256(variableRate)),
                bondAmount,
                interim,
                false
            );

        // assertEq(celineShortTrade.baseProceeds, danShortTrade.baseProceeds);

        // assertLt(
        //     spotFixedRates[0],
        //     spotFixedRates[1],
        //     "fixed rate should increase after celine opening and closing a short"
        // );
        // assertEq(
        //     spotFixedRates[1],
        //     spotFixedRates[2],
        //     "fixed rate should remain the same after accruing a long amount of interest"
        // );
        // assertLt(
        //     spotFixedRates[2],
        //     spotFixedRates[3],
        //     "fixed rate should increase after dan opening and closing a short"
        // );

        // A short is a promise to purchase at a future point in time

        // TODO Discern conditions which would incur this to be higher or lower
        // assertGt(
        //     scenario.celineShortInterestEarned,
        //     scenario.danShortInterestEarned,
        //     "interest earned on shorts should be the same"
        // );

        // // TODO Discern conditions which would incur this to be higher or lower
        // assertLt(
        //     scenario.celineQuotedAPR,
        //     scenario.danQuotedAPR,
        //     "The first quote should imply a better fixed rate than the second"
        // );
    }

    function _scenarioShort(
        int256 variableRate,
        uint256 bondAmount,
        uint256 interim,
        bool immediateClose
    )
        internal
        returns (
            uint256[4] memory spotFixedRates,
            ShortTrade memory celineShortTrade,
            ShortTrade memory danShortTrade
        )
    {
        spotFixedRates[0] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        _makeShortTrade(
            celineShortTrade,
            variableRate,
            bondAmount,
            immediateClose
        );

        spotFixedRates[1] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
        advanceTime(interim, variableRate);
        spotFixedRates[2] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        _makeShortTrade(
            danShortTrade,
            variableRate,
            bondAmount,
            immediateClose
        );

        spotFixedRates[3] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        /// LOGGING ///

        console2.log("# Celine");
        logShortTrade(celineShortTrade);

        console2.log("# Dan");
        logShortTrade(danShortTrade);

        console2.log("\tfixedRate 1:\t\t%s", (spotFixedRates[0]).toPercent());
        console2.log("\tfixedRate 2:\t\t%s", (spotFixedRates[1]).toPercent());
        console2.log("\tfixedRate 3:\t\t%s", (spotFixedRates[2]).toPercent());
        console2.log("\tfixedRate 4:\t\t%s", (spotFixedRates[3]).toPercent());
    }

    function _makeShortTrade(
        ShortTrade memory _trade,
        int256 variableRate,
        uint256 bondAmount,
        bool immediateClose
    ) internal {
        _trade.openSharePrice = hyperdrive.getPoolInfo().sharePrice;
        _trade.openBondPrice = hyperdrive.bondPrice(FixedPointMath.ONE_18);
        _trade.bondAmount = bondAmount;
        // Open and close a short
        (uint256 maturityTime, uint256 basePaid) = openShort(
            celine,
            bondAmount
        );
        _trade.basePaid = basePaid;
        _trade.quotedAPR = HyperdriveUtils.calculateAPRFromRealizedPrice(
            bondAmount - basePaid,
            bondAmount,
            FixedPointMath.ONE_18
        );
        _trade.secondsBackdated =
            block.timestamp -
            hyperdrive.latestCheckpoint();
        if (!immediateClose) {
            advanceTime(POSITION_DURATION, variableRate);
        }
        _trade.closeBondPrice = hyperdrive.bondPrice(
            hyperdrive.calculateTimeRemaining(maturityTime)
        );
        _trade.closeSharePrice = hyperdrive.getPoolInfo().sharePrice;
        _trade.interestEarned = hyperdriveMath.calculateShortInterest(
            bondAmount,
            _trade.openSharePrice,
            _trade.closeSharePrice,
            _trade.closeSharePrice
        );
        _trade.baseProceeds = closeShort(celine, maturityTime, bondAmount);
    }

    function logShortTrade(ShortTrade memory _trade) internal {
        (
            ,
            ,
            uint256 sharePayment,
            uint256 totalLpFee,
            uint256 totalGovernanceFee
        ) = hyperdrive.calculateCloseShortTrade(_trade.bondAmount, 0);

        console2.log("------------");
        console2.log("\tquotedAPR:\t\t%s", _trade.quotedAPR.toPercent());
        console2.log("\tbondAmount:\t\t%s", _trade.bondAmount.toString());
        console2.log("\tsecondsBackdated:\t%s", _trade.secondsBackdated);
        console2.log();
        console2.log(
            "\topenSharePrice:\t\t%s",
            _trade.openSharePrice.toString()
        );
        console2.log(
            "\tcloseSharePrice:\t%s",
            _trade.closeSharePrice.toString()
        );
        console2.log("\topenBondPrice:\t\t%s", _trade.openBondPrice.toString());
        console2.log(
            "\tcloseBondPrice:\t\t%s",
            _trade.closeBondPrice.toString()
        );
        console2.log();
        console2.log("\tbasePaid:\t\t%s", _trade.basePaid.toString());
        console2.log(
            "\tbaseProceeds:\t\t%s\n\t| interestEarned:\t  %s",
            _trade.baseProceeds.toString(),
            _trade.interestEarned.toString()
        );
        console2.log();
        console2.log("\tsharePayment:\t\t%s", sharePayment.toString());
        console2.log(
            "\tsharePaymentLessFee:\t%s (lpFee: %s, governanceFee: %s)",
            (sharePayment - totalLpFee).toString(),
            (totalLpFee - totalGovernanceFee).toString(),
            totalGovernanceFee.toString()
        );

        console2.log("------------");
    }
}
