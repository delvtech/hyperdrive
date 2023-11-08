// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { IMockHyperdrive } from "contracts/test/MockHyperdrive.sol";
import { MockHyperdriveMath } from "contracts/test/MockHyperdriveMath.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract HyperdriveMathTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    function test__calcSpotPrice() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        assertEq(
            hyperdriveMath.calculateSpotPrice(
                1 ether, // shareReserves
                1 ether, // bondReserves
                1 ether, // initialSharePrice
                1 ether // timeStretch
            ),
            1 ether // 1.0 spot price
        );

        assertApproxEqAbs(
            hyperdriveMath.calculateSpotPrice(
                1.1 ether, // shareReserves
                1 ether, // bondReserves
                1 ether, // initialSharePrice
                1 ether // timeStretch
            ),
            1.1 ether, // 1.1 spot price
            1 wei
        );
    }

    function test__calcAPRFromReserves() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // equal reserves should make 0% APR
        assertEq(
            hyperdriveMath.calculateSpotAPR(
                1 ether, // shareReserves
                1 ether, // bondReserves
                1 ether, // initialSharePrice
                365 days, // positionDuration
                1 ether // timeStretch
            ),
            0 // 0% APR
        );

        // target a 10% APR
        assertApproxEqAbs(
            hyperdriveMath.calculateSpotAPR(
                1 ether, // shareReserves
                1.1 ether, // bondReserves
                1 ether, // initialSharePrice
                365 days, // positionDuration
                1 ether // timeStretch
            ),
            0.10 ether, // 10% APR
            2 wei // calculation rounds up 2 wei for some reason
        );

        // target a 10% APR with a 6 month term
        assertApproxEqAbs(
            hyperdriveMath.calculateSpotAPR(
                1 ether, // shareReserves
                1.05 ether, // bondReserves
                1 ether, // initialSharePrice
                182.5 days, // positionDuration
                1 ether // timeStretch
            ),
            0.10 ether, // 10% APR
            4 wei // calculation rounds up 2 wei for some reason
        );
    }

    function test__calculateInitialBondReserves() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test .1% APR
        uint256 shareReserves = 500_000_000 ether;
        uint256 initialSharePrice = 1 ether;
        uint256 apr = 0.001 ether;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = ONE.divDown(1109.3438508425959e18);
        uint256 bondReserves = hyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        uint256 result = hyperdriveMath.calculateSpotAPR(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 20 wei);

        // Test 1% APR
        apr = 0.01 ether;
        timeStretch = ONE.divDown(110.93438508425959e18);
        bondReserves = hyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        result = hyperdriveMath.calculateSpotAPR(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 1 wei);

        // Test 5% APR
        apr = 0.05 ether;
        timeStretch = ONE.divDown(22.186877016851916266e18);
        bondReserves = hyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        result = hyperdriveMath.calculateSpotAPR(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 1 wei);

        // Test 25% APR
        apr = 0.25 ether;
        timeStretch = ONE.divDown(4.437375403370384e18);
        bondReserves = hyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        result = hyperdriveMath.calculateSpotAPR(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 0 wei);

        // Test 50% APR
        apr = 0.50 ether;
        timeStretch = ONE.divDown(2.218687701685192e18);
        bondReserves = hyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        result = hyperdriveMath.calculateSpotAPR(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 1 wei);

        // Test 100% APR
        apr = 1 ether;
        timeStretch = ONE.divDown(1.109343850842596e18);
        bondReserves = hyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        result = hyperdriveMath.calculateSpotAPR(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 4 wei);
    }

    function test__calculateOpenLong() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test open long at 1% APR, No backdating
        uint256 shareReserves = 500_000_000 ether;
        uint256 bondReserves = 2 *
            503_926_401.456553339958190918 ether +
            shareReserves;
        uint256 initialSharePrice = 1 ether;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = ONE.divDown(110.93438508425959e18);
        uint256 expectedAPR = 0.882004326279808182 ether;
        uint256 amountIn = 50_000_000 ether;
        uint256 bondReservesDelta = hyperdriveMath.calculateOpenLong(
            shareReserves,
            bondReserves,
            amountIn,
            timeStretch,
            1 ether, // sharePrice
            initialSharePrice
        );
        bondReserves -= bondReservesDelta;
        shareReserves += amountIn;
        uint256 result = hyperdriveMath.calculateSpotAPR(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        // verify that the resulting APR is correct
        assertApproxEqAbs(result, expectedAPR.divDown(100e18), 3e12);
    }

    function test__calculateCloseLongBeforeMaturity() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test closing the long halfway thru the term that was opened at 1% APR, No backdating
        uint256 shareReserves = 550_000_000 ether;
        uint256 bondReserves = 2 *
            453_456_134.637519001960754395 ether +
            shareReserves;
        uint256 positionDuration = 365 days;
        uint256 normalizedTimeRemaining = 0.5e18;
        uint256 timeStretch = ONE.divDown(110.93438508425959e18);
        uint256 amountIn = 503_926_401.456553339958190918 ether -
            453_456_134.637519001960754395 ether;
        uint256 expectedAPR = 0.9399548487105884 ether;
        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,

        ) = hyperdriveMath.calculateCloseLong(
                shareReserves,
                bondReserves,
                amountIn,
                normalizedTimeRemaining,
                timeStretch,
                1 ether,
                1 ether
            );
        // verify that the poolBondDelta equals the amountIn/2
        assertEq(bondReservesDelta, amountIn.mulDown(normalizedTimeRemaining));
        shareReserves -= shareReservesDelta;
        bondReserves += bondReservesDelta;
        uint256 result = hyperdriveMath.calculateSpotAPR(
            shareReserves,
            bondReserves,
            1 ether,
            positionDuration,
            timeStretch
        );
        // verify that the resulting APR is correct
        assertApproxEqAbs(result, expectedAPR.divDown(100e18), 4e12);
    }

    function test__calculateCloseLongAtMaturity() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test closing the long at maturity that was opened at 1% APR, No backdating
        uint256 shareReserves = 550_000_000 ether;
        uint256 bondReserves = 2 *
            453_456_134.637519001960754395 ether +
            shareReserves;
        uint256 normalizedTimeRemaining = 0;
        uint256 timeStretch = ONE.divDown(110.93438508425959e18);
        uint256 amountIn = 503_926_401.456553339958190918 ether -
            453_456_134.637519001960754395 ether;
        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 shareProceeds
        ) = hyperdriveMath.calculateCloseLong(
                shareReserves,
                bondReserves,
                amountIn,
                normalizedTimeRemaining,
                timeStretch,
                1 ether,
                1 ether
            );
        // verify that the curve part is zero
        assertEq(shareReservesDelta, 0);
        assertEq(bondReservesDelta, 0);
        // verify that the flat part is the amountIn * sharePrice (sharePrice = 1)
        assertEq(shareProceeds, amountIn);
    }

    function test__calculateOpenShort() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test open long at 1% APR, No backdating
        uint256 shareReserves = 500_000_000 ether;
        uint256 bondReserves = 2 *
            503_926_401.456553339958190918 ether +
            shareReserves;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = ONE.divDown(110.93438508425959e18);
        uint256 expectedAPR = 1.1246406058180446 ether;
        {
            uint256 amountIn = 50_000_000 ether;

            uint256 shareReservesDelta = hyperdriveMath.calculateOpenShort(
                shareReserves,
                bondReserves,
                amountIn,
                timeStretch,
                1 ether,
                1 ether
            );
            bondReserves += amountIn;
            shareReserves -= shareReservesDelta;
        }
        uint256 result = hyperdriveMath.calculateSpotAPR(
            shareReserves,
            bondReserves,
            1 ether,
            positionDuration,
            timeStretch
        );
        // verify that the resulting APR is correct
        assertApproxEqAbs(result, expectedAPR.divDown(100e18), 6e12);
    }

    function test__calculateCloseShortAtMaturity() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test closing the long at maturity that was opened at 1% APR, No backdating
        uint256 shareReserves = 450_000_000 ether;
        uint256 bondReserves = 2 *
            554_396_668.275587677955627441 ether +
            shareReserves;
        uint256 normalizedTimeRemaining = 0;
        uint256 timeStretch = ONE.divDown(110.93438508425959e18);
        uint256 amountOut = 50_470_266.819034337997436523 ether;
        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 sharePayment
        ) = hyperdriveMath.calculateCloseShort(
                shareReserves,
                bondReserves,
                amountOut,
                normalizedTimeRemaining,
                timeStretch,
                1 ether,
                1 ether
            );
        // verify that the curve part is zero
        assertEq(shareReservesDelta, 0);
        assertEq(bondReservesDelta, 0);
        // verify that the flat part is the amountOut / sharePrice (sharePrice = 1)
        assertEq(sharePayment, amountOut);
    }

    function test__calculateCloseShortBeforeMaturity() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test closing the long at maturity that was opened at 1% APR, No backdating
        uint256 shareReserves = 450_000_000 ether;
        uint256 bondReserves = 2 *
            554_396_668.275587677955627441 ether +
            shareReserves;
        uint256 positionDuration = 365 days;
        uint256 normalizedTimeRemaining = 0.5e18;
        uint256 timeStretch = ONE.divDown(110.93438508425959e18);
        uint256 amountOut = 50_470_266.819034337997436523 ether;
        uint256 expectedAPR = 1.0621819862950987 ether;
        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,

        ) = hyperdriveMath.calculateCloseShort(
                shareReserves,
                bondReserves,
                amountOut,
                normalizedTimeRemaining,
                timeStretch,
                1 ether,
                1 ether
            );
        // verify that the bondReservesDelta equals the amountOut/2
        assertEq(bondReservesDelta, amountOut.mulDown(normalizedTimeRemaining));
        shareReserves += shareReservesDelta;
        bondReserves -= bondReservesDelta;
        uint256 result = hyperdriveMath.calculateSpotAPR(
            shareReserves,
            bondReserves,
            1 ether,
            positionDuration,
            timeStretch
        );
        // verify that the resulting APR is correct
        assertApproxEqAbs(result, expectedAPR.divDown(100e18), 3e12);
    }

    struct TestCaseInput {
        uint256 closeSharePrice;
        uint256 openSharePrice;
        uint256 shareProceeds;
        uint256 shareReservesDelta;
        uint256 shareCurveDelta;
        uint256 totalGovernanceFee;
    }

    struct TestCaseOutput {
        uint256 shareProceeds;
        uint256 shareReservesDelta;
        uint256 shareCurveDelta;
        uint256 totalGovernanceFee;
        int256 shareAdjustmentDelta;
    }

    function test__calculateNegativeInterestOnClose() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // interest rate of 0%
        {
            TestCaseInput memory input = TestCaseInput({
                closeSharePrice: 1e18,
                openSharePrice: 1e18,
                shareProceeds: 10_000_000e18,
                shareReservesDelta: 10_000_000e18,
                shareCurveDelta: 5_000_000e18,
                totalGovernanceFee: 100_000e18
            });

            // closing a long
            TestCaseOutput memory output;
            (
                output.shareProceeds,
                output.shareReservesDelta,
                output.shareCurveDelta,
                output.shareAdjustmentDelta,
                output.totalGovernanceFee
            ) = hyperdriveMath.calculateNegativeInterestOnClose(
                input.shareProceeds,
                input.shareReservesDelta,
                input.shareCurveDelta,
                input.totalGovernanceFee,
                input.openSharePrice,
                input.closeSharePrice,
                true
            );
            assertEq(output.shareProceeds, input.shareProceeds);
            assertEq(output.shareReservesDelta, input.shareReservesDelta);
            assertEq(output.shareCurveDelta, input.shareCurveDelta);
            assertEq(output.totalGovernanceFee, input.totalGovernanceFee);
            assertEq(
                output.shareAdjustmentDelta,
                int256(input.shareReservesDelta) - int256(input.shareCurveDelta)
            );

            // closing a short
            (
                output.shareProceeds,
                output.shareReservesDelta,
                output.shareCurveDelta,
                output.shareAdjustmentDelta,
                output.totalGovernanceFee
            ) = hyperdriveMath.calculateNegativeInterestOnClose(
                input.shareProceeds,
                input.shareReservesDelta,
                input.shareCurveDelta,
                input.totalGovernanceFee,
                input.openSharePrice,
                input.closeSharePrice,
                false
            );
            assertEq(output.shareProceeds, input.shareProceeds);
            assertEq(output.shareReservesDelta, input.shareReservesDelta);
            assertEq(output.shareCurveDelta, input.shareCurveDelta);
            assertEq(output.totalGovernanceFee, input.totalGovernanceFee);
            assertEq(
                output.shareAdjustmentDelta,
                int256(input.shareReservesDelta) - int256(input.shareCurveDelta)
            );
        }

        // interest rate of 10%
        {
            TestCaseInput memory input = TestCaseInput({
                closeSharePrice: 1.1e18,
                openSharePrice: 1e18,
                shareProceeds: 10_000_000e18,
                shareReservesDelta: 10_000_000e18,
                shareCurveDelta: 5_000_000e18,
                totalGovernanceFee: 100_000e18
            });

            // closing a long
            TestCaseOutput memory output;
            (
                output.shareProceeds,
                output.shareReservesDelta,
                output.shareCurveDelta,
                output.shareAdjustmentDelta,
                output.totalGovernanceFee
            ) = hyperdriveMath.calculateNegativeInterestOnClose(
                input.shareProceeds,
                input.shareReservesDelta,
                input.shareCurveDelta,
                input.totalGovernanceFee,
                input.openSharePrice,
                input.closeSharePrice,
                true
            );
            assertEq(output.shareProceeds, input.shareProceeds);
            assertEq(output.shareReservesDelta, input.shareReservesDelta);
            assertEq(output.shareCurveDelta, input.shareCurveDelta);
            assertEq(output.totalGovernanceFee, input.totalGovernanceFee);
            assertEq(
                output.shareAdjustmentDelta,
                int256(input.shareReservesDelta) - int256(input.shareCurveDelta)
            );

            // closing a short
            (
                output.shareProceeds,
                output.shareReservesDelta,
                output.shareCurveDelta,
                output.shareAdjustmentDelta,
                output.totalGovernanceFee
            ) = hyperdriveMath.calculateNegativeInterestOnClose(
                input.shareProceeds,
                input.shareReservesDelta,
                input.shareCurveDelta,
                input.totalGovernanceFee,
                input.openSharePrice,
                input.closeSharePrice,
                false
            );
            assertEq(output.shareProceeds, input.shareProceeds);
            assertEq(output.shareReservesDelta, input.shareReservesDelta);
            assertEq(output.shareCurveDelta, input.shareCurveDelta);
            assertEq(output.totalGovernanceFee, input.totalGovernanceFee);
            assertEq(
                output.shareAdjustmentDelta,
                int256(input.shareReservesDelta) - int256(input.shareCurveDelta)
            );
        }

        // interest rate of -10%
        {
            TestCaseInput memory input = TestCaseInput({
                closeSharePrice: 0.9e18,
                openSharePrice: 1e18,
                shareProceeds: 10_000_000e18,
                shareReservesDelta: 10_000_000e18,
                shareCurveDelta: 5_000_000e18,
                totalGovernanceFee: 100_000e18
            });

            // closing a long
            TestCaseOutput memory output;
            (
                output.shareProceeds,
                output.shareReservesDelta,
                output.shareCurveDelta,
                output.shareAdjustmentDelta,
                output.totalGovernanceFee
            ) = hyperdriveMath.calculateNegativeInterestOnClose(
                input.shareProceeds,
                input.shareReservesDelta,
                input.shareCurveDelta,
                input.totalGovernanceFee,
                input.openSharePrice,
                input.closeSharePrice,
                true
            );
            assertEq(
                output.shareProceeds,
                input.shareProceeds.mulDivDown(
                    input.closeSharePrice,
                    input.openSharePrice
                )
            );
            assertEq(
                output.shareReservesDelta,
                input.shareReservesDelta.mulDivDown(
                    input.closeSharePrice,
                    input.openSharePrice
                )
            );
            assertEq(
                output.shareCurveDelta,
                input.shareCurveDelta.mulDivDown(
                    input.closeSharePrice,
                    input.openSharePrice
                )
            );
            assertEq(
                output.totalGovernanceFee,
                input.totalGovernanceFee.mulDivDown(
                    input.closeSharePrice,
                    input.openSharePrice
                )
            );
            assertEq(
                output.shareAdjustmentDelta,
                int256(
                    input.shareReservesDelta.mulDown(input.closeSharePrice)
                ) - int256(input.shareCurveDelta)
            );

            // closing a short
            (
                output.shareProceeds,
                output.shareReservesDelta,
                output.shareCurveDelta,
                output.shareAdjustmentDelta,
                output.totalGovernanceFee
            ) = hyperdriveMath.calculateNegativeInterestOnClose(
                input.shareProceeds,
                input.shareReservesDelta,
                input.shareCurveDelta,
                input.totalGovernanceFee,
                input.openSharePrice,
                input.closeSharePrice,
                false
            );
            // NOTE: share proceeds aren't scaled
            assertEq(output.shareProceeds, input.shareProceeds);
            assertEq(
                output.shareReservesDelta,
                input.shareReservesDelta.mulDivDown(
                    input.closeSharePrice,
                    input.openSharePrice
                )
            );
            assertEq(
                output.shareCurveDelta,
                input.shareCurveDelta.mulDivDown(
                    input.closeSharePrice,
                    input.openSharePrice
                )
            );
            assertEq(
                output.totalGovernanceFee,
                input.totalGovernanceFee.mulDivDown(
                    input.closeSharePrice,
                    input.openSharePrice
                )
            );
            assertEq(
                output.shareAdjustmentDelta,
                int256(
                    input.shareReservesDelta.mulDown(input.closeSharePrice)
                ) - int256(input.shareCurveDelta)
            );
        }
    }

    function test__calculateMaxLong__matureLong(
        uint256 fixedRate,
        uint256 contribution,
        uint256 matureLongAmount,
        uint256 initialLongAmount,
        uint256 initialShortAmount,
        uint256 finalLongAmount
    ) external {
        // Deploy Hyperdrive.
        fixedRate = fixedRate.normalizeToRange(0.001e18, 0.5e18);
        deploy(alice, fixedRate, 0, 0, 0);

        // Initialize the Hyperdrive pool.
        contribution = contribution.normalizeToRange(1_000e18, 500_000_000e18);
        initialize(alice, fixedRate, contribution);

        // Open a long position that will be held for an entire term. This will
        // decrease the value of the share adjustment to a non-trivial value.
        matureLongAmount = matureLongAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong() / 2
        );
        openLong(alice, matureLongAmount);
        advanceTime(hyperdrive.getPoolConfig().positionDuration, 0);

        // Ensure that the max long is actually the max long.
        _verifyMaxLong(
            fixedRate,
            initialLongAmount,
            initialShortAmount,
            finalLongAmount
        );
    }

    function test__calculateMaxLong__matureShort(
        uint256 fixedRate,
        uint256 contribution,
        uint256 matureShortAmount,
        uint256 initialLongAmount,
        uint256 initialShortAmount,
        uint256 finalLongAmount
    ) external {
        // Deploy Hyperdrive.
        fixedRate = fixedRate.normalizeToRange(0.001e18, 0.5e18);
        deploy(alice, fixedRate, 0, 0, 0);

        // Initialize the Hyperdrive pool.
        contribution = contribution.normalizeToRange(1_000e18, 500_000_000e18);
        initialize(alice, fixedRate, contribution);

        // Open a short position that will be held for an entire term. This will
        // increase the value of the share adjustment to a non-trivial value.
        matureShortAmount = matureShortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxShort() / 2
        );
        openShort(alice, matureShortAmount);
        advanceTime(hyperdrive.getPoolConfig().positionDuration, 0);

        // Ensure that the max long is actually the max long.
        _verifyMaxLong(
            fixedRate,
            initialLongAmount,
            initialShortAmount,
            finalLongAmount
        );
    }

    function test__calculateMaxLong__edgeCases() external {
        // This is an edge case where pool has a spot price of 1 at the optimal
        // trade size but the optimal trade size is less than the value that we
        // solve for when checking the endpoint.
        _test__calculateMaxLong(
            78006570044966433744465072258,
            0,
            0,
            115763819684266577237839082600338781403556286119250692248603493285535482011337,
            0
        );
    }

    function test__calculateMaxLong__fuzz(
        uint256 fixedRate,
        uint256 contribution,
        uint256 initialLongAmount,
        uint256 initialShortAmount,
        uint256 finalLongAmount
    ) external {
        _test__calculateMaxLong(
            fixedRate,
            contribution,
            initialLongAmount,
            initialShortAmount,
            finalLongAmount
        );
    }

    function _test__calculateMaxLong(
        uint256 fixedRate,
        uint256 contribution,
        uint256 initialLongAmount,
        uint256 initialShortAmount,
        uint256 finalLongAmount
    ) internal {
        // Deploy Hyperdrive.
        fixedRate = fixedRate.normalizeToRange(0.001e18, 0.5e18);
        deploy(alice, fixedRate, 0, 0, 0);

        // Initialize the Hyperdrive pool.
        contribution = contribution.normalizeToRange(1_000e18, 500_000_000e18);
        initialize(alice, fixedRate, contribution);

        // Ensure that the max long is actually the max long.
        _verifyMaxLong(
            fixedRate,
            initialLongAmount,
            initialShortAmount,
            finalLongAmount
        );
    }

    function _verifyMaxLong(
        uint256 fixedRate,
        uint256 initialLongAmount,
        uint256 initialShortAmount,
        uint256 finalLongAmount
    ) internal {
        // Open a long and a short. This sets the long buffer to a non-trivial
        // value which stress tests the max long function.
        initialLongAmount = initialLongAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong() / 2
        );
        openLong(bob, initialLongAmount);
        initialShortAmount = initialShortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxShort() / 2
        );
        openShort(bob, initialShortAmount);

        // TODO: The fact that we need such a large amount of iterations could
        // indicate a bug in the max long function.
        //
        // Open the maximum long on Hyperdrive.
        IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory config = hyperdrive.getPoolConfig();
        uint256 maxIterations = 10;
        if (fixedRate > 0.15e18) {
            maxIterations += 5;
        }
        if (fixedRate > 0.35e18) {
            maxIterations += 5;
        }
        (uint256 maxLong, ) = HyperdriveUtils.calculateMaxLong(
            HyperdriveUtils.MaxTradeParams({
                shareReserves: info.shareReserves,
                shareAdjustment: info.shareAdjustment,
                bondReserves: info.bondReserves,
                longsOutstanding: info.longsOutstanding,
                longExposure: info.longExposure,
                timeStretch: config.timeStretch,
                sharePrice: info.sharePrice,
                initialSharePrice: config.initialSharePrice,
                minimumShareReserves: config.minimumShareReserves,
                curveFee: config.fees.curve,
                governanceFee: config.fees.governance
            }),
            hyperdrive
                .getCheckpoint(hyperdrive.latestCheckpoint())
                .longExposure,
            maxIterations
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, maxLong);

        // TODO: Re-visit this after fixing `calculateMaxLong` to work with
        // matured positions.
        //
        // Ensure that opening another long fails. We fuzz in the range of
        // 10% to 1000x the max long.
        //
        // NOTE: The max spot price increases after we open the first long
        // because the spot price increases. In some cases, this could cause
        // a small trade to suceed after the large trade, so we use relatively
        // large amounts for the second trade.
        vm.stopPrank();
        vm.startPrank(bob);
        finalLongAmount = finalLongAmount.normalizeToRange(
            maxLong.mulDown(0.1e18).max(MINIMUM_TRANSACTION_AMOUNT),
            maxLong.mulDown(1000e18).max(
                MINIMUM_TRANSACTION_AMOUNT.mulDown(10e18)
            )
        );
        baseToken.mint(bob, finalLongAmount);
        baseToken.approve(address(hyperdrive), finalLongAmount);
        vm.expectRevert();
        hyperdrive.openLong(
            finalLongAmount,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that the long can be closed.
        closeLong(bob, maturityTime, longAmount);
    }

    function test__calculateMaxShort__matureLong(
        uint256 fixedRate,
        uint256 contribution,
        uint256 matureLongAmount,
        uint256 initialLongAmount,
        uint256 initialShortAmount,
        uint256 finalShortAmount
    ) external {
        // Initialize the Hyperdrive pool.
        contribution = contribution.normalizeToRange(1_000e18, 500_000_000e18);
        fixedRate = fixedRate.normalizeToRange(0.0001e18, 0.5e18);
        initialize(alice, fixedRate, contribution);

        // Open a long position that will be held for an entire term. This will
        // increase the value of the share adjustment to a non-trivial value.
        matureLongAmount = matureLongAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong() / 2
        );
        openLong(alice, matureLongAmount);
        advanceTime(hyperdrive.getPoolConfig().positionDuration, 0);

        // Ensure that the max short is actually the max short.
        _verifyMaxShort(
            initialLongAmount,
            initialShortAmount,
            finalShortAmount
        );
    }

    function test__calculateMaxShort__matureShort(
        uint256 fixedRate,
        uint256 contribution,
        uint256 matureShortAmount,
        uint256 initialLongAmount,
        uint256 initialShortAmount,
        uint256 finalShortAmount
    ) external {
        // Initialize the Hyperdrive pool.
        contribution = contribution.normalizeToRange(1_000e18, 500_000_000e18);
        fixedRate = fixedRate.normalizeToRange(0.0001e18, 0.5e18);
        initialize(alice, fixedRate, contribution);

        // Open a short position that will be held for an entire term. This will
        // increase the value of the share adjustment to a non-trivial value.
        matureShortAmount = matureShortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxShort() / 2
        );
        openShort(alice, matureShortAmount);
        advanceTime(hyperdrive.getPoolConfig().positionDuration, 0);

        // Ensure that the max short is actually the max short.
        _verifyMaxShort(
            initialLongAmount,
            initialShortAmount,
            finalShortAmount
        );
    }

    function test__calculateMaxShort_fuzz(
        uint256 fixedRate,
        uint256 contribution,
        uint256 initialLongAmount,
        uint256 initialShortAmount,
        uint256 finalShortAmount
    ) external {
        // Initialize the Hyperdrive pool.
        contribution = contribution.normalizeToRange(1_000e18, 500_000_000e18);
        fixedRate = fixedRate.normalizeToRange(0.0001e18, 0.5e18);
        initialize(alice, fixedRate, contribution);

        // Ensure that the max short is actually the max short.
        _verifyMaxShort(
            initialLongAmount,
            initialShortAmount,
            finalShortAmount
        );
    }

    function _verifyMaxShort(
        uint256 initialLongAmount,
        uint256 initialShortAmount,
        uint256 finalShortAmount
    ) internal {
        // Open a long. This sets the long buffer to a non-trivial value which
        // stress tests the max long function.
        initialLongAmount = initialLongAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxLong() / 2
        );
        openLong(bob, initialLongAmount);
        initialShortAmount = initialShortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            hyperdrive.calculateMaxShort() / 2
        );
        openShort(bob, initialShortAmount);

        // Open the maximum short on Hyperdrive.
        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
            hyperdrive.latestCheckpoint()
        );
        IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory config = hyperdrive.getPoolConfig();
        uint256 maxShort = HyperdriveUtils.calculateMaxShort(
            HyperdriveUtils.MaxTradeParams({
                shareReserves: info.shareReserves,
                shareAdjustment: info.shareAdjustment,
                bondReserves: info.bondReserves,
                longsOutstanding: info.longsOutstanding,
                longExposure: info.longExposure,
                timeStretch: config.timeStretch,
                sharePrice: info.sharePrice,
                initialSharePrice: config.initialSharePrice,
                minimumShareReserves: config.minimumShareReserves,
                curveFee: config.fees.curve,
                governanceFee: config.fees.governance
            }),
            checkpoint.longExposure,
            7
        );
        (uint256 maturityTime, ) = openShort(bob, maxShort);

        // Ensure that opening another short fails.
        vm.stopPrank();
        vm.startPrank(bob);
        finalShortAmount = finalShortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            100_000_000e18
        );
        baseToken.mint(bob, finalShortAmount);
        baseToken.approve(address(hyperdrive), finalShortAmount);
        vm.expectRevert();
        hyperdrive.openShort(
            finalShortAmount,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Ensure that the short can be closed.
        closeShort(bob, maturityTime, maxShort);
    }

    // FIXME: Add tests cases with the share adjustment and verify that the
    // changes work properly.
    function test__calculatePresentValue() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        uint256 apr = 0.02e18;
        uint256 initialSharePrice = 1e18;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = HyperdriveUtils.calculateTimeStretch(apr);

        // no open positions.
        {
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    minimumShareReserves: 1e5,
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            uint256 presentValue = hyperdriveMath.calculatePresentValue(params);
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // all longs on the curve.
        {
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 1e18,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            uint256 presentValue = hyperdriveMath.calculatePresentValue(params);
            params.shareReserves -= YieldSpaceMath
                .calculateSharesOutGivenBondsInDown(
                    params.shareReserves,
                    params.bondReserves,
                    params.longsOutstanding,
                    ONE - params.timeStretch,
                    params.sharePrice,
                    params.initialSharePrice
                );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // all longs on the flat.
        {
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 0,
                    shortAverageTimeRemaining: 0
                });
            uint256 presentValue = hyperdriveMath.calculatePresentValue(params);
            params.shareReserves -= params.longsOutstanding.divDown(
                params.sharePrice
            );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // all shorts on the curve.
        {
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 1e18
                });
            uint256 presentValue = hyperdriveMath.calculatePresentValue(params);
            params.shareReserves += YieldSpaceMath
                .calculateSharesInGivenBondsOutUp(
                    params.shareReserves,
                    params.bondReserves,
                    params.shortsOutstanding,
                    ONE - params.timeStretch,
                    params.sharePrice,
                    params.initialSharePrice
                );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // all shorts on the flat.
        {
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 0,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0
                });
            uint256 presentValue = hyperdriveMath.calculatePresentValue(params);
            params.shareReserves += params.shortsOutstanding.divDown(
                params.sharePrice
            );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // longs and shorts completely net.
        {
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 0.3e18,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0.3e18
                });
            uint256 presentValue = hyperdriveMath.calculatePresentValue(params);
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // all shorts on the curve, all longs on the flat.
        {
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 0,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 1e18
                });
            uint256 presentValue = hyperdriveMath.calculatePresentValue(params);
            params.shareReserves += YieldSpaceMath
                .calculateSharesInGivenBondsOutUp(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    params.shortsOutstanding,
                    ONE - params.timeStretch,
                    params.sharePrice,
                    params.initialSharePrice
                );
            params.shareReserves -= params.longsOutstanding.divDown(
                params.sharePrice
            );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // all longs on the curve, all shorts on the flat.
        {
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 1e18,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0
                });
            uint256 presentValue = hyperdriveMath.calculatePresentValue(params);
            params.shareReserves -= YieldSpaceMath
                .calculateSharesOutGivenBondsInDown(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    params.longsOutstanding,
                    ONE - params.timeStretch,
                    params.sharePrice,
                    params.initialSharePrice
                );
            params.shareReserves += params.shortsOutstanding.divDown(
                params.sharePrice
            );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // small amount of longs, large amount of shorts
        {
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 100_000e18,
                    longAverageTimeRemaining: 0.75e18,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0.25e18
                });
            uint256 presentValue = hyperdriveMath.calculatePresentValue(params);

            // net curve short and net flat short
            params.shareReserves += YieldSpaceMath
                .calculateSharesInGivenBondsOutUp(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    params.shortsOutstanding.mulDown(
                        params.shortAverageTimeRemaining
                    ) -
                        params.longsOutstanding.mulDown(
                            params.longAverageTimeRemaining
                        ),
                    ONE - params.timeStretch,
                    params.sharePrice,
                    params.initialSharePrice
                );
            params.shareReserves +=
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.sharePrice
                ) -
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.sharePrice
                );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // large amount of longs, small amount of shorts
        {
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: 500_000_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        500_000_000e18,
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 10_000_000e18,
                    longAverageTimeRemaining: 0.75e18,
                    shortsOutstanding: 100_000e18,
                    shortAverageTimeRemaining: 0.25e18
                });
            uint256 presentValue = hyperdriveMath.calculatePresentValue(params);

            // net curve long and net flat long
            params.shareReserves -= YieldSpaceMath
                .calculateSharesOutGivenBondsInDown(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    params.longsOutstanding.mulDown(
                        params.longAverageTimeRemaining
                    ) -
                        params.shortsOutstanding.mulDown(
                            params.shortAverageTimeRemaining
                        ),
                    ONE - params.timeStretch,
                    params.sharePrice,
                    params.initialSharePrice
                );
            params.shareReserves -=
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.sharePrice
                ) -
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.sharePrice
                );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // small amount of longs, large amount of shorts, no excess liquidity
        //
        // This scenario simulates all of the LPs losing their liquidity. What
        // is important is that the calculation won't fail in this scenario.
        {
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: 100_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        100_000e18,
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e5,
                    timeStretch: timeStretch,
                    longsOutstanding: 100_000e18,
                    longAverageTimeRemaining: 0.75e18,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0.25e18
                });
            uint256 presentValue = hyperdriveMath.calculatePresentValue(params);

            // Apply as much as possible to the curve and mark the rest of the
            // curve trade to the short base volume.
            uint256 netCurveTrade = params.shortsOutstanding.mulDown(
                params.shortAverageTimeRemaining
            ) -
                params.longsOutstanding.mulDown(
                    params.longAverageTimeRemaining
                );
            uint256 maxCurveTrade = YieldSpaceMath.calculateMaxBuy(
                uint256(int256(params.shareReserves) - params.shareAdjustment),
                params.bondReserves,
                ONE - params.timeStretch,
                params.sharePrice,
                params.initialSharePrice
            );
            params.shareReserves += YieldSpaceMath
                .calculateSharesInGivenBondsOutUp(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    maxCurveTrade,
                    ONE - params.timeStretch,
                    params.sharePrice,
                    params.initialSharePrice
                );
            params.shareReserves += netCurveTrade - maxCurveTrade;

            // Apply the flat part to the reserves.
            params.shareReserves +=
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.sharePrice
                ) -
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.sharePrice
                );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }

        // complicated scenario with non-trivial minimum share reserves
        {
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: 100_000e18,
                    shareAdjustment: 0,
                    bondReserves: calculateBondReserves(
                        100_000e18,
                        initialSharePrice,
                        apr,
                        positionDuration,
                        timeStretch
                    ),
                    sharePrice: 2e18,
                    initialSharePrice: 1e18,
                    minimumShareReserves: 1e18,
                    timeStretch: timeStretch,
                    longsOutstanding: 100_000e18,
                    longAverageTimeRemaining: 0.75e18,
                    shortsOutstanding: 10_000_000e18,
                    shortAverageTimeRemaining: 0.25e18
                });
            uint256 presentValue = hyperdriveMath.calculatePresentValue(params);

            // Apply as much as possible to the curve and mark the rest of the
            // curve trade to the short base volume.
            uint256 netCurveTrade = params.shortsOutstanding.mulDown(
                params.shortAverageTimeRemaining
            ) -
                params.longsOutstanding.mulDown(
                    params.longAverageTimeRemaining
                );
            uint256 maxCurveTrade = YieldSpaceMath.calculateMaxBuy(
                uint256(int256(params.shareReserves) - params.shareAdjustment),
                params.bondReserves,
                ONE - params.timeStretch,
                params.sharePrice,
                params.initialSharePrice
            );
            params.shareReserves += YieldSpaceMath
                .calculateSharesInGivenBondsOutUp(
                    uint256(
                        int256(params.shareReserves) - params.shareAdjustment
                    ),
                    params.bondReserves,
                    maxCurveTrade,
                    ONE - params.timeStretch,
                    params.sharePrice,
                    params.initialSharePrice
                );
            params.shareReserves += netCurveTrade - maxCurveTrade;

            // Apply the flat part to the reserves.
            params.shareReserves +=
                params.shortsOutstanding.mulDivDown(
                    1e18 - params.shortAverageTimeRemaining,
                    params.sharePrice
                ) -
                params.longsOutstanding.mulDivDown(
                    1e18 - params.longAverageTimeRemaining,
                    params.sharePrice
                );
            assertEq(
                presentValue,
                params.shareReserves - params.minimumShareReserves
            );
        }
    }

    function test__calculateShortProceeds() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // 0% interest - 5% margin released - 0% interest after close
        uint256 bondAmount = 1.05e18;
        uint256 shareAmount = 1e18;
        uint256 openSharePrice = 1e18;
        uint256 closeSharePrice = 1e18;
        uint256 sharePrice = 1e18;
        uint256 flatFee = 0;
        uint256 shortProceeds = hyperdriveMath.calculateShortProceeds(
            bondAmount,
            shareAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / share_price = (0.05 + 0) / 1
        assertEq(shortProceeds, 0.05e18);

        // 5% interest - 5% margin released - 0% interest after close
        bondAmount = 1.05e18;
        openSharePrice = 1e18;
        closeSharePrice = 1.05e18;
        sharePrice = 1.05e18;
        shareAmount = uint256(1e18).divDown(sharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceeds(
            bondAmount,
            shareAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / share_price = (0.05 + 1.05 * 0.05) / 1.05
        assertApproxEqAbs(
            shortProceeds,
            (0.05e18 + bondAmount.mulDown(0.05e18)).divDown(sharePrice),
            1
        );

        // 5% interest - 0% margin released - 0% interest after close
        bondAmount = 1e18;
        openSharePrice = 1e18;
        closeSharePrice = 1.05e18;
        sharePrice = 1.05e18;
        shareAmount = uint256(1e18).divDown(sharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceeds(
            bondAmount,
            shareAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / share_price = (0 + 1 * 0.05) / 1.05
        assertApproxEqAbs(
            shortProceeds,
            (bondAmount.mulDown(0.05e18)).divDown(sharePrice),
            1
        );

        // 5% interest - 5% margin released - 10% interest after close
        bondAmount = 1.05e18;
        openSharePrice = 1e18;
        closeSharePrice = 1.05e18;
        sharePrice = 1.155e18;
        shareAmount = uint256(1e18).divDown(sharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceeds(
            bondAmount,
            shareAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / share_price = (0.05 + 1.05 * 0.05) / 1.155
        assertApproxEqAbs(
            shortProceeds,
            (0.05e18 + bondAmount.mulDown(0.05e18)).divDown(sharePrice),
            1
        );

        // -10% interest - 5% margin released - 0% interest after close
        bondAmount = 1.05e18;
        openSharePrice = 1e18;
        closeSharePrice = 0.9e18;
        sharePrice = 0.9e18;
        shareAmount = uint256(1e18).divDown(sharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceeds(
            bondAmount,
            shareAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice,
            flatFee
        );
        assertEq(shortProceeds, 0);

        // -10% interest - 5% margin released - 20% interest after close
        bondAmount = 1.05e18;
        openSharePrice = 1e18;
        closeSharePrice = 0.9e18;
        sharePrice = 1.08e18;
        shareAmount = uint256(1e18).divDown(sharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceeds(
            bondAmount,
            shareAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice,
            flatFee
        );
        assertEq(shortProceeds, 0);

        // 5% interest - 0% margin released - 0% interest after close
        // 50% flatFee applied
        bondAmount = 1e18;
        openSharePrice = 1e18;
        closeSharePrice = 1.05e18;
        sharePrice = 1.05e18;
        shareAmount = uint256(1e18).divDown(sharePrice);
        flatFee = 0.5e18;
        shortProceeds = hyperdriveMath.calculateShortProceeds(
            bondAmount,
            shareAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / share_price
        //            + (bondAmount * flatFee) / share_price
        //          = (0 + 1 * 0.05) / 1.05 + (1 * 0.5) / 1.05
        assertApproxEqAbs(
            shortProceeds,
            (bondAmount.mulDown(0.05e18)).divDown(sharePrice) +
                (bondAmount.mulDivDown(flatFee, sharePrice)),
            1
        );

        // 5% interest - 5% margin released - 0% interest after close
        bondAmount = 1.05e18;
        openSharePrice = 1e18;
        closeSharePrice = 1.05e18;
        sharePrice = 1.05e18;
        shareAmount = uint256(1e18).divDown(sharePrice);
        flatFee = 0.25e18;
        shortProceeds = hyperdriveMath.calculateShortProceeds(
            bondAmount,
            shareAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / share_price
        //            + (bondAmount * flatFee) / share_price
        //          = ((0.05 + 1.05 * 0.05) / 1.05) + ((1 * 0.25) / 1.05)
        assertApproxEqAbs(
            shortProceeds,
            (0.05e18 + bondAmount.mulDown(0.05e18)).divDown(sharePrice) +
                bondAmount.mulDivDown(flatFee, sharePrice),
            1
        );
    }

    function test__calculateTimeRemainingScaledAndUnscaled(
        uint256 maturityTime
    ) external {
        maturityTime = maturityTime.normalizeToRange(
            block.timestamp,
            block.timestamp * 1e6
        );

        // Ensure that the calculate time remaining calculation is correct.
        uint256 result = IMockHyperdrive(address(hyperdrive))
            .calculateTimeRemaining(maturityTime);
        assertEq(
            result,
            (maturityTime -
                IMockHyperdrive(address(hyperdrive)).latestCheckpoint())
                .divDown(hyperdrive.getPoolConfig().positionDuration)
        );

        // Ensure that the scaled and unscaled time remaining calculations agree.
        uint256 scaledResult = IMockHyperdrive(address(hyperdrive))
            .calculateTimeRemainingScaled(maturityTime * ONE);
        assertEq(result, scaledResult);
    }

    function calculateBondReserves(
        uint256 _shareReserves,
        uint256 _initialSharePrice,
        uint256 _apr,
        uint256 _positionDuration,
        uint256 _timeStretch
    ) internal pure returns (uint256 bondReserves) {
        // Solving for (1 + r * t) ** (1 / tau) here. t is the normalized time remaining which in
        // this case is 1. Because bonds mature after the positionDuration, we need to scale the apr
        // to the proportion of a year of the positionDuration. tau = t / time_stretch, or just
        // 1 / time_stretch in this case.
        uint256 t = _positionDuration.divDown(365 days);
        uint256 tau = ONE.mulDown(_timeStretch);
        uint256 interestFactor = (ONE + _apr.mulDown(t)).pow(ONE.divDown(tau));

        // bondReserves = mu * z * (1 + apr * t) ** (1 / tau)
        bondReserves = _initialSharePrice.mulDown(_shareReserves).mulDown(
            interestFactor
        );
        return bondReserves;
    }
}
