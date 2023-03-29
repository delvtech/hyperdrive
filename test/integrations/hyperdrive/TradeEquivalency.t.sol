// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";

contract ConsistentLong is HyperdriveTest {
    using FixedPointMath for uint256;

    // fails before increasing minimum variable rate to be above > 5% (was > 0%)
    // and first time advancement and interest accrual was only a POSITION_DURATION
    //
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

    // fails before increasing the minimum base amount from >= 1 to >= 1000
    //
    // [50000000000000001, 1000000000000000000, 157680000] - > 5e8 profit diff
    // [187193209094729690, 221128669109828433612, 1839502638] - > 1e18 profit diff
    // [83175496718313302, 751973074152545661370733, 187183518] - > 1000e18 profit diff
    // [123292750307666052, 1142768296576811082, 2617522713] - error NegativeInterest()
    // [206080415846754655, 216715518936758579342, 2100824088] - error FixedPointMath_SubOverflow()
    // [152717399717226279, 11851101164171121898, 2147390823] - error NegativeInterest()
    // [398114559986209304, 7370358606027960523, 877488382] - error NegativeInterest()

    // [247030295238303486, 1000000000000000000000, 1718604736] - error NegativeInterest()
    // [50000000000000001, 958091509226410150635070, 157680000] - > 10000e18 diff
    // [50000000000000001, 2790642879033877301272218, 157680000] - > 100000e18 diff
    // [50000000000000001, 2650487052294783603626154, 157680000 - fixed rate diff > 1 BP
    function test_long_equivalency_variable_gt_fixed(
        int256 variableRate,
        uint256 baseAmount,
        uint256 interim
    ) external {
        uint256 fixedRate = 0.05e18;

        // 5% < variableRate < 100%
        vm.assume(variableRate < 1e18);
        vm.assume(variableRate > int256(fixedRate));

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

        uint256 fixedRate1 = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);

        // Celine opens a long
        (uint256 celineMaturityTime, uint256 celineBondAmount) = openLong(celine, baseAmount);

        // Advance a duration accruing variable rate
        advanceTime(POSITION_DURATION, variableRate);

        // Celine closes her long and calculates her profits
        (uint256 celineBaseAmount) = closeLong(celine, celineMaturityTime, celineBondAmount);
        uint256 celineProfits = celineBaseAmount - baseAmount;

        // Advance the interim amount of time accruing variable rate
        advanceTime(interim, variableRate);

        uint256 fixedRate2 = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);

        // Dan opens a long
        (uint256 danMaturityTime, uint256 danBondAmount) = openLong(dan, baseAmount);

        // Advance a duration accruing variable rate
        advanceTime(POSITION_DURATION, variableRate);

        // Dan closes his long and calculates his profits
        (uint256 danBaseAmount) = closeLong(dan, danMaturityTime, danBondAmount);
        uint256 danProfits = danBaseAmount - baseAmount;

        assertApproxEqAbs(danProfits, celineProfits, 500000e18, "users long profits should be equal");
        assertApproxEqAbs(fixedRate1, fixedRate2, 1e14, "fixed rate for both users should be within 1 basis point delta");
    }
}
