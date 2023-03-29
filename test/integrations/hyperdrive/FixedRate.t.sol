// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";

contract ConsistentLong is HyperdriveTest {
    using FixedPointMath for uint256;

    // [433008150368160477, 2004459342514105984026, 968944808] - error NegativeInterest()
    //
    function test_fixed_rate_does_not_change_from_positive_interest_accrual(
        int256 variableRate,
        uint256 baseAmount,
        uint256 interim
    ) external {
        uint256 fixedRate = 0.05e18;

        // 5% < variableRate < 100%
        vm.assume(variableRate < 1e18);
        vm.assume(variableRate >= 0);

        // 1 < baseAmount < 5,000,000
        vm.assume(baseAmount < 5_000_000e18);
        vm.assume(baseAmount >= 1000e18);

        // 5 years <= interim <= 100 years
        vm.assume(interim >= POSITION_DURATION * 5);
        vm.assume(interim <= POSITION_DURATION * 100);

        // Initialize the pool with capital.
        uint256 initialLiquidity = 500_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);

        // Advance the interim amount of time accruing variable rate
        advanceTime(interim, variableRate);

        uint256 spotFixedRate1 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long so that system accounting is cycled
        (uint256 celineMaturityTime, uint256 celineBondAmount) = openLong(
            celine,
            baseAmount
        );
        closeLong(celine, celineMaturityTime, celineBondAmount);

        uint256 spotFixedRate2 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Advance the interim amount of time accruing variable rate
        advanceTime(interim, variableRate);

        uint256 spotFixedRate3 = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );

        // Open and close a long
        (uint256 danMaturityTime, uint256 danBondAmount) = openLong(
            dan,
            baseAmount
        );
        closeLong(dan, danMaturityTime, danBondAmount);

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
