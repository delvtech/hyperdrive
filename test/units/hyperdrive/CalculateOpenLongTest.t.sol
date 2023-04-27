// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { MockHyperdrive } from "../../mocks/MockHyperdrive.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";

// Assumptions:
//
// - The "state" values were arbitraily selected with a bias to non-rounded
//   figures.
// - Where fractional values are indicated in commentary, the utilised value is
//   its fixed point representation rounded down to 18 decimals.
// - Calculations as stated in the assertion commentary are derived using
//   WolframAlpha and are generally represented in a form exceeding 18 decimals
// - Values in assertions are the fixed point representation of the WolframAlpha
//   results rounded (down unless otherwise stated) to 18 decimals.
// - "Hand-rolled" calculations which are dependent on results from other
//   calculations use the 18 decimal precision representation which will incur
//   some precision loss from the mathematically "true" value of these
//   computations.
contract CalculateOpenLongTest is HyperdriveTest {
    using FixedPointMath for uint256;

    // State variables
    uint256 initialSharePrice;
    uint256 sharePrice;
    uint256 normalizedTimeRemaining;
    uint256 shareAmount;
    uint256 bondReserves;
    uint256 shareReserves;
    uint256 timeStretch;
    IHyperdrive.Fees fees;

    // Intermediary calculation variables
    uint256 dz_curve;
    uint256 dy_$_flat;
    uint256 one_minus_t_stretch;
    uint256 c_div_mu;
    uint256 mu_z;
    uint256 mu_z_pow_one_minus_t_stretch;
    uint256 y_pow_one_minus_t_stretch;
    uint256 k;
    uint256 mu_z_and_dzcurve;
    uint256 mu_z_and_dzcurve_pow_one_minus_t_stretch;
    uint256 z_;
    uint256 inverse_one_minus_t_stretch;
    uint256 _y;
    uint256 dy_$_curve;
    uint256 dy;
    uint256 tau;
    uint256 p;
    uint256 flat_fee;
    uint256 curve_fee;
    uint256 governance_flat_fee;
    uint256 governance_curve_fee;

    // Assertion variables
    uint256 expectedTotalGovernanceFee;
    uint256 expectedBondReservesDelta;
    uint256 expectedBondProceeds;
    uint256 expectedShareReservesDelta;

    function test_calculate_open_long() external {
        // µ = 1 * 45/41
        initialSharePrice = 1.097560975609756097e18;
        // c = 1 * 49/41
        sharePrice = 1.195121951219512195e18;
        // t = 34/35
        normalizedTimeRemaining = 0.971428571428571428e18;
        // Δx = c · Δz
        // Δz = Δx / c
        // Δz = 100000 / 1.195121951219512195
        // Δz = 83673.469387755102049354
        shareAmount = 83673.469387755102049354e18;
        // y = 100000000 * 7672/1998.5
        bondReserves = 383887915.936952714535901926e18;
        // z = 100000000 * 7672/2149 - 20,000,000
        shareReserves = 337003257.328990228013029315e18;
        // 1 / (3.09396 / (0.02789 * 5))
        // timeStretch = 0.045071688063194094e18;
        timeStretch = HyperdriveUtils.calculateTimeStretch(0.05e18);

        // State setup
        fees = IHyperdrive.Fees({
            curve: 0.025e18, // 2.5%
            flat: 0.03e18, // 3%
            governance: 0.425e18 // 42.5%
        });

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

        // Δz_curve = Δz · t
        // Δz_curve = 83673.469387755102049354 * 0.971428571428571428
        // Δz_curve = 81282.798833819241942987617492711370257512
        dz_curve = shareAmount.mulDown(normalizedTimeRemaining);
        assertEq(dz_curve, 81282.798833819241942987e18, "dz_curve");

        // Δy'flat = Δz · (1 - t) * c
        // Δy'flat = 83673.469387755102049354 * (1 - 0.971428571428571428) * 1.195121951219512195
        // Δy'flat = 2857.14285714285719999998512408447699634341676740382564116
        dy_$_flat = shareAmount
            .mulDown(FixedPointMath.ONE_18.sub(normalizedTimeRemaining))
            .mulDown(sharePrice);
        assertEq(dy_$_flat, 2857.142857142857199999e18, "dy_apost_flat");

        // For the curve trade, (1 - t) is reframed as (1 - timeStretch)
        // (1 - t) = (1 - 0.045071688063194094)
        // (1 - t) = 0.954928311936805906
        one_minus_t_stretch = FixedPointMath.ONE_18.sub(timeStretch);
        assertEq(
            one_minus_t_stretch,
            0.954928311936805906e18,
            "one_minus_t_stretch"
        );

        // (c / µ) = (1.195121951219512195 / 1.097560975609756097)
        // (c / µ) = 1.0888888888888888893343209876543209878819862825788751715841263222...
        c_div_mu = sharePrice.divDown(initialSharePrice);
        assertEq(c_div_mu, 1.088888888888888889e18, "c_div_mu");

        // (µ · z) = (1.097560975609756097 * 337003257.328990228013029315)
        // (µ · z) = 369881623.897672201288664494059346945260983555
        mu_z = initialSharePrice.mulDown(shareReserves);
        assertEq(mu_z, 369881623.897672201288664494e18, "mu_z");

        // (µ · z)^(1 - t) = 369881623.897672201288664494^(0.954928311936805906)
        // (µ · z)^(1 - t) = 152014740.974500528173941042763114476815073326183010430
        mu_z_pow_one_minus_t_stretch = initialSharePrice
            .mulDown(shareReserves)
            .pow(one_minus_t_stretch);
        assertApproxEqAbs(
            mu_z_pow_one_minus_t_stretch,
            152014740.974500528173941042e18,
            5e7,
            "mu_z_pow_one_minus_t"
        ); // TODO Precision

        // y^(1 - t) = (383887915.936952714535901926)^(0.954928311936805906)
        // y^(1 - t) = 157506998.923528080399004587041700209859953096737243167
        y_pow_one_minus_t_stretch = bondReserves.pow(one_minus_t_stretch);
        assertApproxEqAbs(
            y_pow_one_minus_t_stretch,
            157506998.923528080399004587e18,
            3e8,
            "y_pow_one_minus_t_stretch"
        ); // TODO Precision

        // k = (c / µ) · (µ · z)^(1 - t) + y^(1 - t)
        // k = 1.088888888888888889 * 152014740.974500528173941042 + 157506998.923528080399004587
        // k = 323034161.317984211094186470619388947574882338
        k = c_div_mu.mulDown(mu_z_pow_one_minus_t_stretch).add(
            y_pow_one_minus_t_stretch
        );
        assertApproxEqAbs(k, 323034161.31798421109418647e18, 3e8, "k"); // TODO Precision

        // (µ · (z + Δz_curve)) = 1.097560975609756097 * (337003257.328990228013029315 + 81282.798833819241942987)
        // (µ · (z + Δz_curve)) = 369970836.725660539480995345538049924710625294
        mu_z_and_dzcurve = initialSharePrice.mulDown(
            shareReserves.add(dz_curve)
        );
        assertEq(
            mu_z_and_dzcurve,
            369970836.725660539480995345e18,
            "mu_z_and_dzcurve"
        );

        // (µ · (z + Δz_curve))^(1 - t) = 369970836.725660539480995345^0.954928311936805906
        // (µ · (z + Δz_curve))^(1 - t) = 152049753.115098833898787866715676618030157129075568782
        mu_z_and_dzcurve_pow_one_minus_t_stretch = mu_z_and_dzcurve.pow(
            one_minus_t_stretch
        );
        assertApproxEqAbs(
            mu_z_and_dzcurve_pow_one_minus_t_stretch,
            152049753.115098833898787866e18,
            5e7,
            "mu_z_and_dzcurve_pow_one_minus_t_stretch"
        ); // TODO Precision

        // (c / µ) · (µ · (z + Δz_curve))^(1 - t) = 1.088888888888888889 * 152049753.115098833898787866
        // (c / µ) · (µ · (z + Δz_curve))^(1 - t) = 165565286.725329841373352315546122092655420874
        z_ = c_div_mu.mulDown(mu_z_and_dzcurve_pow_one_minus_t_stretch);
        assertApproxEqAbs(z_, 165565286.725329841373352315e18, 5e7, "z_"); // TODO Precision

        // (1 / (1 - t)) = 1 / 0.954928311936805906
        // (1 / (1 - t)) = 1.0471990279267966596926226784985107956999882836058167426007625189...
        inverse_one_minus_t_stretch = FixedPointMath.ONE_18.divUp(
            one_minus_t_stretch
        );
        assertEq(
            inverse_one_minus_t_stretch,
            1.04719902792679666e18, // Rounded up
            "inverse_one_minus_t_stretch"
        );

        // (k - (c / µ) · (µ · (z + Δz_curve))^(1 - t))^(1 / (1 - t)) = (323034161.31798421109418647 - 165565286.725329841373352315)^1.04719902792679666
        // (k - (c / µ) · (µ · (z + Δz_curve))^(1 - t))^(1 / (1 - t)) = (157468874.592654369720834155)^1.04719902792679666
        // (k - (c / µ) · (µ · (z + Δz_curve))^(1 - t))^(1 / (1 - t)) = 383790611.293791832749419609975176889050228160919979985
        _y = k.sub(z_).pow(inverse_one_minus_t_stretch);
        assertApproxEqAbs(_y, 383790611.293791832749419609e18, 7e8, "_y"); // TODO Precision

        // Δy'curve = y - (k - (c / µ) · (µ · (z + Δz_curve))^(1 - t))^(1 / (1 - t))
        // Δy'curve = 383887915.936952714535901926 - 383790611.293791832749419609
        // Δy'curve = 97304.643160881786482317
        dy_$_curve = bondReserves.sub(_y);
        assertApproxEqAbs(
            dy_$_curve,
            97304.643160881786482317e18,
            7e8,
            "dy_apost_curve"
        ); // TODO Precision

        // Δy = Δ'y_curve + Δ'y_flat
        // Δy = 97304.643160881786482317 + 2857.142857142857199999
        // Δy = 100161.786018024643682316
        dy = dy_$_curve.add(dy_$_flat);
        assertApproxEqAbs(dy, 100161.786018024643682316e18, 7e8, "dy");

        // τ = t * timeStretch
        // τ = 0.971428571428571428 * 0.045071688063194094
        // τ = 0.043783925547102834145673321106746232
        tau = normalizedTimeRemaining.mulDown(timeStretch);
        assertEq(tau, 0.043783925547102834e18, "tau");

        // p = (µ · z / y)^τ
        // p = (369881623.897672201288664494 / 383887915.936952714535901926)^0.043783925547102834
        // p = (0.9635146315947574221524973828409339252968448231146639381459727054)^0.043783925547102834
        // p = 0.9983739797397207901274666301517165600456415425139442692974
        p = mu_z.divDown(bondReserves).pow(tau);
        assertEq(p, 0.99837397973972079e18, "p");

        // flat_fee = c · Δz · (1 - t) · Φ_flat
        // flat_fee = 1.195121951219512195 * 83673.469387755102049354 * (1 - 0.971428571428571428) * (3/100)
        // flat_fee = 85.7142857142857159999995537225343098903025030221147692348
        flat_fee = sharePrice
            .mulDown(shareAmount)
            .mulDown(FixedPointMath.ONE_18.sub(normalizedTimeRemaining))
            .mulDown(fees.flat);
        assertEq(flat_fee, 85.714285714285715999e18, "flat_fee");

        // curve_fee = ((1 / p) - 1) · Φ_curve * c · Δz · t
        // curve_fee = ((1 / 0.99837397973972079) - 1) * (2.5/100) * 1.195121951219512195 * 83673.469387755102049354 * 0.971428571428571428
        // curve_fee = 3.9553378058008476341813458022271009778187353456297919835792269030
        curve_fee = (
            (FixedPointMath.ONE_18.divDown(p)).sub(FixedPointMath.ONE_18)
        ).mulDown(fees.curve).mulDown(sharePrice).mulDown(shareAmount).mulDown(
                normalizedTimeRemaining
            );
        assertApproxEqAbs(curve_fee, 3.955337805800847634e18, 2e5, "curve_fee");

        // governance_flat_fee = (flat_fee · Φ_governance)
        // governance_flat_fee = (85.714285714285715999 * 42.5/100)
        // governance_flat_fee = 36.428571428571429299575
        governance_flat_fee = flat_fee.mulDown(fees.governance);
        assertEq(
            governance_flat_fee,
            36.428571428571429299e18,
            "governance_flat_fee"
        );

        // governance_curve_fee = Δz * (curve_fee / Δy) * c * Φ_governance
        // governance_curve_fee = 83673.469387755102049354 * (3.955337805800847634 / 100161.786018024643682316) * 1.195121951219512195 * (42.5/100)
        // governance_curve_fee = 1.678303307373983979665963589851097667486890664120111384375177702967713899401845398...
        governance_curve_fee = shareAmount
            .mulDivDown(curve_fee, dy)
            .mulDown(sharePrice)
            .mulDown(fees.governance);
        assertApproxEqAbs(
            governance_curve_fee,
            1.678303307373983979e18,
            6e4,
            "governance_curve_fee"
        ); // TODO Precision

        // governance_fee = (governance_flat_fee + governance_curve_fee) / c
        // governance_fee = (36.428571428571429299 + 1.678303307373983979) / 1.195121951219512195
        // governance_fee = 31.88534416681146825627401471089912941390551170519378871570464405155038660364333102...
        expectedTotalGovernanceFee = (
            governance_flat_fee.add(governance_curve_fee)
        ).divDown(sharePrice);
        assertApproxEqAbs(
            expectedTotalGovernanceFee,
            31.885344166811468256e18,
            5e4,
            "expectedTotalGovernanceFee"
        ); // TODO Precision

        // bondReservesDelta = Δ'y_curve - (curve_fee - governance_curve_fee)
        // bondReservesDelta = 97304.643160881786482317 - (3.955337805800847634 - 1.678303307373983979)
        // bondReservesDelta = 97302.373979129693414529
        expectedBondReservesDelta = dy_$_curve.sub(
            curve_fee.sub(governance_curve_fee)
        );
        assertApproxEqAbs(
            expectedBondReservesDelta,
            97302.366126383359618662e18,
            7e8,
            "expectedBondReservesDelta"
        ); // TODO Precision

        // bondProceeds = Δy - (curve_fee + flat_fee)
        // bondProceeds = 100161.786018024643682316 - (3.955337805800847634 + 85.714285714285715999)
        // bondProceeds = 100072.116394504557118683
        expectedBondProceeds = dy.sub(curve_fee.add(flat_fee));
        assertApproxEqAbs(
            expectedBondProceeds,
            100072.116394504557118683e18,
            7e8,
            "expectedBondProceeds"
        ); // TODO Precision

        // shareReservesDelta = Δz_curve - (governance_curve_fee / c)
        // shareReservesDelta = 81282.798833819241942987 - (1.678303307373983979 / 1.195121951219512195)
        // shareReservesDelta = 81281.39453921511269108606078626488477021418987614947803777695815062749775895683246...
        expectedShareReservesDelta = dz_curve.sub(
            governance_curve_fee.divDown(sharePrice)
        );
        assertApproxEqAbs(
            expectedShareReservesDelta,
            81281.394539215112691086e18,
            5e4,
            "expectedShareReservesDelta"
        ); // TODO Precision

        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 bondProceeds,
            uint256 totalGovernanceFee
        ) = MockHyperdrive(address(hyperdrive)).calculateOpenLong(
                shareAmount,
                normalizedTimeRemaining
            );

        assertEq(
            shareReservesDelta,
            expectedShareReservesDelta,
            "shareReservesDelta computation misaligned"
        );
        assertEq(
            bondReservesDelta,
            expectedBondReservesDelta,
            "bondReservesDelta computation misaligned"
        );
        assertEq(
            bondProceeds,
            expectedBondProceeds,
            "bondProceeds computation misaligned"
        );
        assertEq(
            totalGovernanceFee,
            expectedTotalGovernanceFee,
            "totalGovernanceFee computation misaligned"
        );

        // Adding explicit delta assertions so that any change in how these
        // values are derived will fail the test
        // TODO Precision
        assertWithDelta(
            shareReservesDelta,
            -49215,
            81281.394539215112691086e18
        );
        assertWithDelta(
            bondReservesDelta,
            -691486610,
            97302.366126383359618662e18
        );
        assertWithDelta(bondProceeds, -691545427, 100072.116394504557118683e18);
        assertWithDelta(totalGovernanceFee, 49214, 31.885344166811468256e18);
    }
}
