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

    function test_calculate_open_long() external {
        // µ = 1 * 45/41
        uint256 initialSharePrice = 1.097560975609756097e18;
        // c = 1 * 49/41
        uint256 sharePrice = 1.195121951219512195e18;
        // t = 34/35
        uint256 normalizedTimeRemaining = 0.971428571428571428e18;

        // Δx = c · Δz
        // Δz = Δx / c
        // Δz = 100000 / 1.195121951219512195
        // Δz = 83673.469387755102049354
        uint256 shareAmount = 83673.469387755102049354e18;

        IHyperdrive.Fees memory fees = IHyperdrive.Fees({
            curve: 0.025e18, // 2.5%
            flat: 0.03e18, // 3%
            governance: 0.425e18 // 42.5%
        });

        // y = 100000000 * 7672/1998.5
        uint256 bondReserves = 383_887_915.936952714535901926e18;
        // z = 100000000 * 7672/2149 - 20,000,000
        uint256 shareReserves = 337_003_257.328990228013029315e18;

        // 1 / (3.09396 / (0.02789 * 5))
        uint256 timeStretch = 0.045071688063194094e18;
        hyperdrive = IHyperdrive(
            address(
                new MockHyperdrive(
                    baseToken,
                    initialSharePrice,
                    CHECKPOINTS_PER_TERM,
                    CHECKPOINT_DURATION,
                    timeStretch,
                    fees,
                    governance
                )
            )
        );

        MockHyperdrive(address(hyperdrive)).setReserves(
            shareReserves,
            bondReserves
        );

        //
        // Math derived using:
        //   https://keisan.casio.com/calculator
        //

        // HyperdriveMath.calculateOpenLong

        // Δz_curve = Δz · t
        // Δz_curve = 83673.469387755102049354 * 0.971428571428571428
        // Δz_curve = 81282.798833819241942987

        // Δy'flat = Δz · (1 - t)
        // Δy'flat = 83673.469387755102049354 * (1 - 0.971428571428571428)
        // Δy'flat = 2390.670553935860106366

        // Δy'curve = I_BoundsOutSharesIn(Δz · t)
        // Δy'curve = y - (k - (c / µ) · (µ · (z + Δz_curve))^(1 - t))^(1 / (1 - t))
        //
        // For the curve trade, (1 - t) is reframed as (1 - timeStretch)
        // (1 - t) = (1 - 0.045071688063194094)
        // (1 - t) = 0.954928311936805906
        //
        // (c / µ) = (1.195121951219512195 / 1.097560975609756097)
        // (c / µ) = 1.088888888888888889
        //
        // k = (c / µ) · (µ · z)^(1 - t) + y^(1 - t)
        // k = (1.088888888888888889) * (1.097560975609756097 * 337003257.328990228013029315)^(0.954928311936805906) + (383887915.936952714535901926)^(0.954928311936805906)
        // k = 1.088888888888888889 * 152014740.974500528173941042 + 157506998.923528080399004587
        // k = 323034161.31798421109418647
        //
        // (µ · (z + Δz_curve))^(1 - t) = (1.097560975609756097 * (337003257.328990228013029315 + 81282.798833819241942987))^0.954928311936805906
        // (µ · (z + Δz_curve))^(1 - t) = 152049753.115098833898787866
        //
        //(c / µ) · (µ · (z + Δz_curve))^(1 - t) = 1.088888888888888889 * 152049753.115098833898787866
        //(c / µ) · (µ · (z + Δz_curve))^(1 - t) = 165565286.725329841373352315
        //
        // (1 / (1 - t)) = 1 / 0.954928311936805906
        // (1 / (1 - t)) = 1.047199027926796659
        //
        // (k - (c / µ) · (µ · (z + Δz_curve))^(1 - t))^(1 / (1 - t)) = (323034161.31798421109418647 - 165565286.725329841373352315)^1.047199027926796659
        // (k - (c / µ) · (µ · (z + Δz_curve))^(1 - t))^(1 / (1 - t)) = 383790611.29379182550547223
        //
        // Δy'curve = y - (k - (c / µ) · (µ · (z + Δz_curve))^(1 - t))^(1 / (1 - t))
        // Δy'curve = 383887915.936952714535901926 - 383790611.29379182550547223
        // Δy'curve = 97304.643160889030429696

        // Spot price

        // τ = t * timeStretch
        // τ = 0.971428571428571428 * 0.045071688063194094
        // τ = 0.043783925547102834

        // p = (µ · z / y)^τ
        // p = ((1.097560975609756097 * 337003257.328990228013029315) / 383887915.936952714535901926)^0.043783925547102834
        // p = 0.99837397973972079

        // _calculateFeesOutGivenSharesIn

        // flat_fee = c · Δz · (1 - t) · Φ_flat
        // flat_fee = 1.195121951219512195 * 83673.469387755102049354 * (1 - 0.971428571428571428) * (3/100)
        // flat_fee = 85.714285714285715999

        // curve_fee = ((1 / p) - 1) · c · Δz · t · Φ_curve
        // curve_fee = ((1 / 0.99837397973972079) - 1) * 1.195121951219512195 * 83673.469387755102049354 * 0.971428571428571428 * (2.5/100)
        // curve_fee = 3.955337805800847634

        // governance_flat_fee = (flat_fee · Φ_governance)
        // governance_flat_fee = (85.714285714285715999 * 42.5/100)
        // governance_flat_fee = 36.428571428571429299

        // governance_curve_fee = (curve_fee · Φ_governance)
        // governance_curve_fee = (3.955337805800847634 * 42.5/100)
        // governance_curve_fee = 1.681018567465360244

        // governance_fee = ((flat_fee · Φ_governance) + (curve_fee · Φ_governance)) / c
        // governance_fee = (36.428571428571429299 + 1.681018567465360244) / 1.195121951219512195
        // governance_fee = 38.109589996036789544 / 1.195121951219512195
        // governance_fee = 31.887616119132823907

        // attribute fees

        // Δy_flat = Δy'flat - flat_fee
        // Δy_flat = 2390.670553935860106366 - 85.714285714285715999
        // Δy_flat = 2304.956268221574390367

        // Δy_curve = Δy'curve - curve_fee
        // Δy_curve = 97304.643160889030429696 - 3.955337805800847634
        // Δy_curve = 97300.687823083229582062

        // bondReservesDelta = Δy_curve - governance_curve_fee
        // bondReservesDelta = 97300.687823083229582062 - 1.681018567465360244
        // bondReservesDelta = 97299.006804515764221818

        // bondProceeds = Δy_curve + Δy_flat
        // bondProceeds = 97300.687823083229582062 + 2304.956268221574390367
        // bondProceeds = 99605.644091304803972429

        // shareReservesDelta = Δz_curve - (governance_curve_fee / c)
        // shareReservesDelta = 81282.798833819241942987 - (1.681018567465360244 / 1.195121951219512195)
        // shareReservesDelta = 81281.392267262791335435

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

        // NOTE - Discrepancy in figures is most likely differences in how exponentiation is derived
        assertApproxEqAbs(
            bondReservesDelta,
            97299.006804515764221818e18,
            3367174614620678992,
            "bondReservesDelta"
        );
        assertApproxEqAbs(
            shareReservesDelta,
            81281.392267262791335435e18,
            4298712978301605,
            "shareReservesDelta"
        );
        assertApproxEqAbs(
            bondProceeds,
            99605.644091304803972429e18,
            6552401952,
            "bondProceeds"
        );
        assertApproxEqAbs(
            totalGovernanceFee,
            31.887616119132823907e18,
            4298712978301605,
            "totalGovernanceFee"
        );
    }
}
