// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { MockHyperdrive } from "contracts/test/MockHyperdrive.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";

contract CalculateOpenLongTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_calculate_open_long(
        uint256 shareAmount,
        uint16 _sharePrice,
        uint16 _timeOffset
    ) external {
        vm.assume(shareAmount >= 1e18 && shareAmount < 50_000_00e18);
        vm.assume(_sharePrice < 500);

        uint256 normalizedTimeRemaining = 1e18 - uint256(_timeOffset);
        uint256 sharePrice = 1e18 + (uint256(_sharePrice) * 1e14);

        console2.log("sharePrice", sharePrice);
        IHyperdrive.MarketState memory marketState = IHyperdrive.MarketState({
            shareReserves: 100_000_000e18,
            bondReserves: 100_000_000e18,
            longsOutstanding: 0,
            shortsOutstanding: 0
        });

        IHyperdrive.Fees memory fees = IHyperdrive.Fees({
            curve: 0.01e18,
            flat: 0.01e18,
            governance: 0.5e18
        });

        MockHyperdrive(address(hyperdrive)).overrideState(
            MockHyperdrive.State({ marketState: marketState, fees: fees })
        );

        CalculationOutputs memory outputs = _calculateExpectedValues(
            CalculationInputs({
                shareAmount: shareAmount,
                sharePrice: sharePrice,
                normalizedTimeRemaining: normalizedTimeRemaining,
                shareReserves: marketState.shareReserves,
                bondReserves: marketState.bondReserves,
                fees: fees,
                timeStretch: hyperdrive.timeStretch(),
                initialSharePrice: hyperdrive.initialSharePrice()
            })
        );

        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 bondProceeds,
            uint256 totalGovernanceFee
        ) = MockHyperdrive(address(hyperdrive)).calculateOpenLong(
                shareAmount,
                sharePrice,
                normalizedTimeRemaining
            );

        assertEq(
            outputs.expectedShareReservesDelta,
            shareReservesDelta,
            "shareReservesDelta"
        );
        assertEq(
            outputs.expectedBondReservesDelta,
            bondReservesDelta,
            "bondReservesDelta"
        );
        assertApproxEqAbs(
            outputs.expectedBondProceeds,
            bondProceeds,
            1e10,
            "bondProceeds"
        );
        assertApproxEqAbs(
            outputs.expectedTotalGovernanceFee,
            totalGovernanceFee,
            1e10,
            "totalGovernanceFee"
        );
    }

    struct CalculationInputs {
        // _calculateOpenLong inputs
        uint256 shareAmount;
        uint256 sharePrice;
        uint256 normalizedTimeRemaining;
        // Hyperdrive state
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 timeStretch;
        uint256 initialSharePrice;
        IHyperdrive.Fees fees;
    }

    struct CalculationOutputs {
        uint256 expectedShareReservesDelta;
        uint256 expectedBondReservesDelta;
        uint256 expectedBondProceeds;
        uint256 expectedTotalGovernanceFee;
    }

    function _calculateExpectedValues(
        CalculationInputs memory _inputs
    ) internal view returns (CalculationOutputs memory outputs) {
        // If backdating occurs, the fraction of shares which corresponds to
        // the amount of time which has passed in the duration period are
        // held back. These shares which are withheld are considered
        // "matured bonds"
        outputs.expectedBondProceeds = _inputs.shareAmount.mulDown(
            FixedPointMath.ONE_18.sub(_inputs.normalizedTimeRemaining)
        );

        // The remaining fraction of shares
        outputs.expectedShareReservesDelta = _inputs.shareAmount.mulDown(
            _inputs.normalizedTimeRemaining
        );

        // Shares are exchanged for bonds on YieldSpace curve
        outputs.expectedBondReservesDelta = YieldSpaceMath
            .calculateBondsOutGivenSharesIn(
                _inputs.shareReserves,
                _inputs.bondReserves,
                outputs.expectedShareReservesDelta,
                FixedPointMath.ONE_18.sub(_inputs.timeStretch),
                _inputs.sharePrice,
                _inputs.initialSharePrice
            );

        // Total amount of bonds are the "fully matured" bonds (withheld
        // shares) and the outcome of the Yieldspace swap
        outputs.expectedBondProceeds += outputs.expectedBondReservesDelta;

        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            _inputs.shareReserves,
            _inputs.bondReserves,
            _inputs.initialSharePrice,
            _inputs.normalizedTimeRemaining,
            _inputs.timeStretch
        );

        uint256 totalCurveFee = (FixedPointMath.ONE_18.divDown(spotPrice)).sub(
            FixedPointMath.ONE_18
        );

        totalCurveFee = totalCurveFee
            .mulDown(_inputs.fees.curve)
            .mulDown(_inputs.sharePrice)
            .mulDown(_inputs.shareAmount)
            .mulDown(_inputs.normalizedTimeRemaining);

        uint256 totalFlatFee = _inputs.shareAmount.mulDown(
            FixedPointMath.ONE_18.sub(_inputs.normalizedTimeRemaining)
        );

        totalFlatFee = totalFlatFee.mulDown(_inputs.sharePrice).mulDown(
            _inputs.normalizedTimeRemaining
        );

        uint256 governanceCurveFee = _inputs
            .shareAmount
            .mulDivDown(totalCurveFee, outputs.expectedBondProceeds)
            .mulDown(_inputs.sharePrice)
            .mulDown(_inputs.fees.governance);

        uint256 governanceFlatFee = totalFlatFee.mulDown(
            _inputs.fees.governance
        );

        outputs.expectedBondReservesDelta -= totalCurveFee - governanceCurveFee;
        outputs.expectedBondProceeds -= totalCurveFee + totalFlatFee;
        outputs.expectedShareReservesDelta -= governanceCurveFee.divDown(
            _inputs.sharePrice
        );
        outputs.expectedTotalGovernanceFee = (governanceCurveFee +
            governanceFlatFee).divDown(_inputs.sharePrice);
    }
}
