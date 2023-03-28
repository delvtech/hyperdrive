// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";

contract ConsistentLong is HyperdriveTest {
    using FixedPointMath for uint256;

    // fails;
    // [89310717164555354, 19294305171346, 2759986588] - error NegativeInterest()
    // [1000000000000001, 90139656031677460444662, 1272053404] - > 20e18 diff
    // [505589294969094780, 5967598015004036415, 1229150615] - error NegativeInterest()
    // [2222943537895924, 184980417359247443861349, 734215285] - > 50e18 diff
    // [799643921134989668, 37927757284188484344153, 1313373041] - error FixedPointMath_SubOverflow()
    // [29710990994185249, 177563206454668603800367, 388497635] - > 100e18 diff
    // [38759787902364067, 292012231115599430911065, 381943213] - > 250e18 diff
    // [179155003119979212, 10870485534840, 1218015120] - > error NegativeInterest()
    // [27890000000000000, 944738916810301234036192, 411866021] - > 1000e18 diff
    // [900602611391976164, 28705840756903878, 1899244800] - > Evm Revert
    function test_consistent_long_positive_interest(
        // int256 variableRate,
        // uint256 baseAmount,
        // uint256 timeBetweenLongs
    ) external {
        // vm.assume(variableRate < 1e18);
        // vm.assume(variableRate > 0.001e18);
        // vm.assume(baseAmount < 5_000_000e18);
        // vm.assume(baseAmount > 0.00001e18);
        // vm.assume(timeBetweenLongs >= POSITION_DURATION * 5);
        // vm.assume(timeBetweenLongs <= POSITION_DURATION * 100);


        int256 variableRate = 1000000000000001;
        uint256 baseAmount = 90139656031677460444662;
        uint256 timeBetweenLongs = 1272053404;

        // Initialize the pool with capital.
        uint256 initialLiquidity = 500_000_000e18;
        initialize(alice, 0.05e18, initialLiquidity);

        // Advance a duration accruing variable rate
        advanceTime(POSITION_DURATION, variableRate);

        // Celine opens a long
        (uint256 celineMaturityTime, uint256 celineBondAmount) = openLong(celine, baseAmount);

        // Advance a duration accruing variable rate
        advanceTime(POSITION_DURATION, variableRate);

        // Celine closes her long and calculates her profits
        (uint256 celineBaseAmount) = closeLong(celine, celineMaturityTime, celineBondAmount);
        uint256 celineProfits = celineBaseAmount - baseAmount;

        // Advance a considerable amount of time accruing variable rate
        advanceTime(timeBetweenLongs, variableRate);

        // Dan opens a long
        (uint256 danMaturityTime, uint256 danBondAmount) = openLong(dan, baseAmount);

        // Advance a duration accruing variable rate
        advanceTime(POSITION_DURATION, variableRate);

        // Dan closes his long and calculates his profits
        (uint256 danBaseAmount) = closeLong(dan, danMaturityTime, danBondAmount);
        uint256 danProfits = danBaseAmount - baseAmount;

        assertApproxEqAbs(danProfits, celineProfits, 5000e18, "profits of longs should be equal");
    }
}
