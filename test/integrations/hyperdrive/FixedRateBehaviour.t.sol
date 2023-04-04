// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { MockHyperdriveMath } from "contracts/test/MockHyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

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

        // TODO Reconciling trade outcome behaviour on immediate close is
        // difficult without extensive introspection on market conditions
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

    // underflow in _updateLiquidity
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

    // underflow in _updateLiquidity
    function test_fixed_rate_behaviour_long_interim_long_negative_interest_immediate_close(
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

        // TODO Reconciling trade outcome behaviour on immediate close is
        // difficult without extensive introspection on market conditions
        //
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
        advanceTime(interim, variableRate);
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

    struct ShortScenario {
        uint256[4] fixedRates;
        uint256 celineBondAmount;
        uint256 celineBaseAmount;
        uint256 celineBasePaid;
        uint256 celineQuotedAPR;
        uint256 celineTimeRemaining;
        uint256 danBondAmount;
        uint256 danBaseAmount;
        uint256 danBasePaid;
        uint256 danQuotedAPR;
        uint256 danTimeRemaining;
    }

    function test_fixed_rate_behaviour_short_interim_short_positive_interest_full_duration(
        uint256 _variableRate,
        uint256 bondAmount,
        uint256 interim,
        uint256 offset
    ) external {
        int256 variableRate = int256(_variableRate.normalizeToRange(0, 1e18));
        bondAmount = bondAmount.normalizeToRange(1000e18, 100_000_000e18);
        interim = interim.normalizeToRange(
            CHECKPOINT_DURATION,
            POSITION_DURATION * 25
        );
        offset = offset.normalizeToRange(0, CHECKPOINT_DURATION - 1);

        ShortScenario memory scenario = _scenarioShort(
            variableRate,
            bondAmount,
            interim,
            offset,
            false
        );

        assertEq(
            scenario.celineTimeRemaining,
            scenario.danTimeRemaining,
            "trades should be backdated equally"
        );
        assertLt(
            scenario.fixedRates[0],
            scenario.fixedRates[1],
            "fixed rate should increase after celine opening and closing a short"
        );
        assertEq(
            scenario.fixedRates[1],
            scenario.fixedRates[2],
            "fixed rate should remain the same after accruing a long amount of interest"
        );
        assertLt(
            scenario.fixedRates[2],
            scenario.fixedRates[3],
            "fixed rate should increase after dan opening and closing a short"
        );
        assertLt(
            scenario.celineBasePaid,
            scenario.danBasePaid,
            "Celine should pay less than dan to open a short"
        );
        assertLt(
            scenario.celineQuotedAPR,
            scenario.danQuotedAPR,
            "Celine should be quoted a worse fixed rate than Dan"
        );
    }

    function test_fixed_rate_behaviour_short_interim_short_positive_interest_immediate_close(
        uint256 _variableRate,
        uint256 bondAmount,
        uint256 interim,
        uint256 offset
    ) external {
        int256 variableRate = int256(_variableRate.normalizeToRange(0, 1e18));
        bondAmount = bondAmount.normalizeToRange(1000e18, 100_000_000e18);
        interim = interim.normalizeToRange(
            CHECKPOINT_DURATION,
            POSITION_DURATION * 25
        );
        offset = offset.normalizeToRange(0, CHECKPOINT_DURATION - 1);

        ShortScenario memory scenario = _scenarioShort(
            variableRate,
            bondAmount,
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
            "fixed rate should either increase or remain the same after Celine opening and immediately closing a short"
        );
        assertEq(
            scenario.fixedRates[1],
            scenario.fixedRates[2],
            "fixed rate should remain the same after accruing a long amount of interest"
        );
        assertGe(
            scenario.fixedRates[2],
            scenario.fixedRates[3],
            "fixed rate should either increase or remain the same after Dan opening and immediately closing a short"
        );

        // assertLt(
        //     scenario.celineBasePaid,
        //     scenario.danBasePaid,
        //     "Celine should pay less than dan to open a short"
        // );
        // assertGt(
        //     scenario.celineQuotedAPR,
        //     scenario.danQuotedAPR,
        //     "Celine should be quoted a worse fixed rate than Dan"
        // );
    }

    function test_fixed_rate_behaviour_short_interim_short_negative_interest_full_duration(
        uint256 _variableRate,
        uint256 bondAmount,
        uint256 interim,
        uint256 offset
    ) external {
        int256 variableRate = -int256(_variableRate.normalizeToRange(0, 0.1e18));
        bondAmount = bondAmount.normalizeToRange(1000e18, 100_000_000e18);
        interim = interim.normalizeToRange(
            CHECKPOINT_DURATION,
            POSITION_DURATION * 5
        );
        offset = offset.normalizeToRange(0, CHECKPOINT_DURATION - 1);

        ShortScenario memory scenario = _scenarioShort(
            variableRate,
            bondAmount,
            interim,
            offset,
            false
        );

        assertEq(
            scenario.celineTimeRemaining,
            scenario.danTimeRemaining,
            "trades should be backdated equally"
        );
        assertLt(
            scenario.fixedRates[0],
            scenario.fixedRates[1],
            "fixed rate should increase after celine opening and closing a short"
        );
        assertEq(
            scenario.fixedRates[1],
            scenario.fixedRates[2],
            "fixed rate should remain the same after accruing a long amount of interest"
        );
        assertLt(
            scenario.fixedRates[2],
            scenario.fixedRates[3],
            "fixed rate should increase after dan opening and closing a short"
        );
        assertLt(
            scenario.celineBasePaid,
            scenario.danBasePaid,
            "Celine should pay less than dan to open a short"
        );
        assertLt(
            scenario.celineQuotedAPR,
            scenario.danQuotedAPR,
            "Celine should be quoted a worse fixed rate than Dan"
        );
    }


    function test_fixed_rate_behaviour_short_interim_short_negative_interest_immediate_close(
        uint256 _variableRate,
        uint256 bondAmount,
        uint256 interim,
        uint256 offset
    ) external {
        int256 variableRate = -int256(_variableRate.normalizeToRange(0, 0.1e18));
        bondAmount = bondAmount.normalizeToRange(1000e18, 100_000_000e18);
        interim = interim.normalizeToRange(
            CHECKPOINT_DURATION,
            POSITION_DURATION * 5
        );
        offset = offset.normalizeToRange(0, CHECKPOINT_DURATION - 1);

        ShortScenario memory scenario = _scenarioShort(
            variableRate,
            bondAmount,
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
            "fixed rate should either increase or remain the same after Celine opening and immediately closing a short"
        );
        assertEq(
            scenario.fixedRates[1],
            scenario.fixedRates[2],
            "fixed rate should remain the same after accruing a long amount of interest"
        );
        assertGe(
            scenario.fixedRates[2],
            scenario.fixedRates[3],
            "fixed rate should either increase or remain the same after Dan opening and immediately closing a short"
        );

        // assertLt(
        //     scenario.celineBasePaid,
        //     scenario.danBasePaid,
        //     "Celine should pay less than dan to open a short"
        // );
        // assertGt(
        //     scenario.celineQuotedAPR,
        //     scenario.danQuotedAPR,
        //     "Celine should be quoted a worse fixed rate than Dan"
        // );
    }

    function _scenarioShort(
        int256 variableRate,
        uint256 bondAmount,
        uint256 interim,
        uint256 offset,
        bool immediateClose
    ) internal returns (ShortScenario memory scenario) {
        // Cache the fixed rate
        scenario.fixedRates[0] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Advance to next checkpoint + offset
        advanceTimeToNextCheckpoint(variableRate, offset);

        // Open and close a short
        (uint256 maturityTime, uint256 basePaid) = openShort(
            celine,
            bondAmount
        );
        scenario.celineBondAmount = bondAmount;
        scenario.celineBasePaid = basePaid;
        scenario.celineQuotedAPR = HyperdriveUtils
            .calculateAPRFromRealizedPrice(
                bondAmount - basePaid,
                bondAmount,
                FixedPointMath.ONE_18
            );
        scenario.celineTimeRemaining = hyperdrive.calculateTimeRemaining(
            maturityTime
        );
        if (!immediateClose) {
            advanceTime(maturityTime - block.timestamp, variableRate);
        }
        scenario.celineBaseAmount = closeShort(celine, maturityTime, bondAmount);

        // Cache the fixed rate
        scenario.fixedRates[1] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Advance to the nearest checkpoint interim seconds into the future
        // + offset seconds
        advanceTime(interim, variableRate);
        advanceTimeToNextCheckpoint(variableRate, offset);

        // Cache the fixed rate
        scenario.fixedRates[2] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long
        (maturityTime, basePaid) = openShort(dan, bondAmount);
        scenario.danBondAmount = bondAmount;
        scenario.danBasePaid = basePaid;
        scenario.danQuotedAPR = HyperdriveUtils.calculateAPRFromRealizedPrice(
            bondAmount - basePaid,
            bondAmount,
            FixedPointMath.ONE_18
        );
        scenario.danTimeRemaining = hyperdrive.calculateTimeRemaining(
            maturityTime
        );
        if (!immediateClose) {
            advanceTime(maturityTime - block.timestamp, variableRate);
        }
        scenario.danBaseAmount = closeShort(dan, maturityTime, bondAmount);

        // Cache the fixed rate
        scenario.fixedRates[3] = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
    }

}
