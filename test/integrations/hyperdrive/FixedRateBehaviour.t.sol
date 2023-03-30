// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";

contract FixedRateBehaviour is HyperdriveTest {
    using FixedPointMath for uint256;

    // May fail if variable interest is large and interim > 50 years with a
    // NegativeInterest() error
    function test_fixed_rate_behaviour_long_interim_long_positive_interest(
        uint64 _variableRate,
        uint256 baseAmount,
        uint32 interim
    ) external {
        uint256 fixedRate = 0.05e18;

        // 0.0001% < variableRate < 100%
        vm.assume(_variableRate > 0.0001e18);
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

        uint256 spotFixedRate1 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long so that system accounting is cycled
        (uint256 celineMaturityTime, uint256 celineBondAmount) = openLong(
            celine,
            baseAmount
        );

        advanceTime(block.timestamp - celineMaturityTime, variableRate);

        uint256 celineBaseAmount = closeLong(
            celine,
            celineMaturityTime,
            celineBondAmount
        );

        uint256 spotFixedRate2 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Advance the interim amount of time accruing variable rate
        advanceTime(uint256(interim), variableRate);

        uint256 spotFixedRate3 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long
        (uint256 danMaturityTime, uint256 danBondAmount) = openLong(
            dan,
            baseAmount
        );

        advanceTime(block.timestamp - danMaturityTime, variableRate);

        uint256 danBaseAmount = closeLong(dan, danMaturityTime, danBondAmount);

        uint256 spotFixedRate4 = HyperdriveUtils.calculateAPRFromReserves(
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

        assertEq(
            (celineBaseAmount - baseAmount).divDown(baseAmount),
            HyperdriveUtils.calculateAPRFromRealizedPrice(
                baseAmount,
                celineBondAmount,
                POSITION_DURATION
            )
        );

        // assertApproxEqAbs(
        //     danProfits,
        //     celineProfits,
        //     500000e18,
        //     "users long profits should be equal"
        // );
        // assertApproxEqAbs(
        //     fixedRate1,
        //     fixedRate2,
        //     1e14,
        //     "fixed rate for both users should be within 1 basis point delta"
        // );
    }
}
