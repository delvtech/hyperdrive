// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { LPMath } from "../../../contracts/src/libraries/LPMath.sol";
import { ERC20ForwarderFactory } from "../../../contracts/src/token/ERC20ForwarderFactory.sol";
import { IMockHyperdrive } from "../../../contracts/test/MockHyperdrive.sol";
import { MockHyperdriveMath } from "../../../contracts/test/MockHyperdriveMath.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract HyperdriveMathTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    uint256 internal constant PRECISION_THRESHOLD = 1e14;

    function test__calculateEffectiveShareReserves() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test effective share reserves equal to zero.
        assertEq(
            hyperdriveMath.calculateEffectiveShareReserves(
                1 ether, // shareReserves
                1 ether // shareAdjustment
            ),
            0 ether
        );

        // Test effective share reserves greater than zero.
        assertEq(
            hyperdriveMath.calculateEffectiveShareReserves(
                2 ether, // shareReserves
                1 ether // shareAdjustment
            ),
            1 ether
        );

        // Test effective share reserves less than zero
        vm.expectRevert(IHyperdrive.InsufficientLiquidity.selector);
        hyperdriveMath.calculateEffectiveShareReserves(
            1 ether, // shareReserves
            2 ether // shareAdjustment
        );
    }

    function test__calcSpotPrice() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        assertEq(
            hyperdriveMath.calculateSpotPrice(
                1 ether, // shareReserves
                1 ether, // bondReserves
                1 ether, // initialVaultSharePrice
                1 ether // timeStretch
            ),
            1 ether // 1.0 spot price
        );

        assertApproxEqAbs(
            hyperdriveMath.calculateSpotPrice(
                1.1 ether, // shareReserves
                1 ether, // bondReserves
                1 ether, // initialVaultSharePrice
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
                1 ether, // initialVaultSharePrice
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
                1 ether, // initialVaultSharePrice
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
                1 ether, // initialVaultSharePrice
                182.5 days, // positionDuration
                1 ether // timeStretch
            ),
            0.10 ether, // 10% APR
            4 wei // calculation rounds up 2 wei for some reason
        );
    }

    function test__calculateOpenLong() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test open long at 1% APR, No backdating
        uint256 shareReserves = 500_000_000 ether;
        uint256 bondReserves = 2 *
            503_926_401.456553339958190918 ether +
            shareReserves;
        uint256 initialVaultSharePrice = 1 ether;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = ONE.divDown(110.93438508425959e18);
        uint256 expectedAPR = 0.882004326279808182 ether;
        uint256 amountIn = 50_000_000 ether;
        uint256 bondReservesDelta = hyperdriveMath.calculateOpenLong(
            shareReserves,
            bondReserves,
            amountIn,
            timeStretch,
            1 ether, // vaultSharePrice
            initialVaultSharePrice
        );
        bondReserves -= bondReservesDelta;
        shareReserves += amountIn;
        uint256 result = hyperdriveMath.calculateSpotAPR(
            shareReserves,
            bondReserves,
            initialVaultSharePrice,
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
        // verify that the flat part is the amountIn * vaultSharePrice (vaultSharePrice = 1)
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
        // verify that the flat part is the amountOut / vaultSharePrice (vaultSharePrice = 1)
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
        assertEq(bondReservesDelta, amountOut.mulUp(normalizedTimeRemaining));
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

    function test__OpenLongCloseLongSymmetry(
        uint256 amountIn,
        uint256 fixedRate
    ) external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        fixedRate = fixedRate.normalizeToRange(0.005e18, 1e18);
        uint256 initialShareReserves = 500_000_000e18;
        uint256 initialVaultSharePrice = INITIAL_SHARE_PRICE;
        uint256 timeStretch = hyperdriveMath.calculateTimeStretch(
            fixedRate,
            POSITION_DURATION
        );
        uint256 normalizedTimeRemaining = 1e18;
        (, int256 initialShareAdjustment, uint256 initialBondReserves) = LPMath
            .calculateInitialReserves(
                initialShareReserves,
                initialVaultSharePrice,
                initialVaultSharePrice,
                fixedRate,
                POSITION_DURATION,
                timeStretch
            );
        uint256 initialEffectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                initialShareReserves,
                initialShareAdjustment
            );
        uint256 effectiveShareReserves = initialEffectiveShareReserves;
        uint256 bondReserves = initialBondReserves;
        uint256 baseAmountIn = amountIn.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            initialShareReserves / 2
        );
        uint256 bondAmountIn;
        uint256 _initialVaultSharePrice = initialVaultSharePrice; // Avoid stack too deep error
        {
            uint256 bondReservesDelta = hyperdriveMath.calculateOpenLong(
                effectiveShareReserves,
                bondReserves,
                baseAmountIn,
                timeStretch,
                _initialVaultSharePrice, // vaultSharePrice
                _initialVaultSharePrice
            );
            bondReserves -= bondReservesDelta;
            effectiveShareReserves += baseAmountIn;
            bondAmountIn = bondReservesDelta;
        }

        {
            uint256 _timeStretch = timeStretch; // Avoid stack too deep error
            uint256 _normalizedTimeRemaining = normalizedTimeRemaining; // Avoid stack too deep error
            MockHyperdriveMath _hyperdriveMath = hyperdriveMath; // Avoid stack too deep error
            (
                uint256 shareReservesDelta,
                uint256 bondReservesDelta,

            ) = _hyperdriveMath.calculateCloseLong(
                    effectiveShareReserves,
                    bondReserves,
                    bondAmountIn,
                    _normalizedTimeRemaining,
                    _timeStretch,
                    _initialVaultSharePrice, // vaultSharePrice
                    _initialVaultSharePrice
                );
            bondReserves += bondReservesDelta;
            effectiveShareReserves -= shareReservesDelta;
            assertApproxEqAbs(
                effectiveShareReserves,
                initialEffectiveShareReserves,
                PRECISION_THRESHOLD
            );
            assertEq(bondReserves, initialBondReserves);
        }
    }

    function test__OpenLongOpenShortSymmetry(
        uint256 amountIn,
        uint256 fixedRate
    ) external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        fixedRate = fixedRate.normalizeToRange(0.005e18, 1e18);
        uint256 initialShareReserves = 500_000_000e18;
        uint256 initialVaultSharePrice = INITIAL_SHARE_PRICE;
        uint256 timeStretch = hyperdriveMath.calculateTimeStretch(
            fixedRate,
            POSITION_DURATION
        );
        (, int256 initialShareAdjustment, uint256 initialBondReserves) = LPMath
            .calculateInitialReserves(
                initialShareReserves,
                initialShareReserves,
                initialVaultSharePrice,
                fixedRate,
                POSITION_DURATION,
                timeStretch
            );
        uint256 initialEffectiveShareReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                initialShareReserves,
                initialShareAdjustment
            );
        uint256 effectiveShareReserves = initialEffectiveShareReserves;
        uint256 bondReserves = initialBondReserves;
        uint256 baseAmountIn = amountIn.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            initialShareReserves / 2
        );
        uint256 bondAmountIn;
        uint256 _initialVaultSharePrice = initialVaultSharePrice; // Avoid stack too deep error
        {
            uint256 bondReservesDelta = hyperdriveMath.calculateOpenLong(
                effectiveShareReserves,
                bondReserves,
                baseAmountIn,
                timeStretch,
                _initialVaultSharePrice, // vaultSharePrice
                _initialVaultSharePrice
            );
            bondReserves -= bondReservesDelta;
            effectiveShareReserves += baseAmountIn;
            bondAmountIn = bondReservesDelta;
        }

        {
            uint256 shareReservesDelta = hyperdriveMath.calculateOpenShort(
                effectiveShareReserves,
                bondReserves,
                bondAmountIn,
                timeStretch,
                _initialVaultSharePrice, // vaultSharePrice
                _initialVaultSharePrice
            );
            bondReserves += bondAmountIn;
            effectiveShareReserves -= shareReservesDelta;
            assertApproxEqAbs(
                effectiveShareReserves,
                initialEffectiveShareReserves,
                PRECISION_THRESHOLD
            );
            assertEq(bondReserves, initialBondReserves);
        }
    }

    struct TestCaseInput {
        uint256 closeVaultSharePrice;
        uint256 openVaultSharePrice;
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
                closeVaultSharePrice: 1e18,
                openVaultSharePrice: 1e18,
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
                input.openVaultSharePrice,
                input.closeVaultSharePrice,
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
                input.openVaultSharePrice,
                input.closeVaultSharePrice,
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
                closeVaultSharePrice: 1.1e18,
                openVaultSharePrice: 1e18,
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
                input.openVaultSharePrice,
                input.closeVaultSharePrice,
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
                input.openVaultSharePrice,
                input.closeVaultSharePrice,
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
                closeVaultSharePrice: 0.9e18,
                openVaultSharePrice: 1e18,
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
                input.openVaultSharePrice,
                input.closeVaultSharePrice,
                true
            );
            assertEq(
                output.shareProceeds,
                input.shareProceeds.mulDivDown(
                    input.closeVaultSharePrice,
                    input.openVaultSharePrice
                )
            );
            assertEq(
                output.shareReservesDelta,
                input.shareReservesDelta.mulDivDown(
                    input.closeVaultSharePrice,
                    input.openVaultSharePrice
                )
            );
            assertEq(
                output.shareCurveDelta,
                input.shareCurveDelta.mulDivDown(
                    input.closeVaultSharePrice,
                    input.openVaultSharePrice
                )
            );
            assertEq(
                output.totalGovernanceFee,
                input.totalGovernanceFee.mulDivDown(
                    input.closeVaultSharePrice,
                    input.openVaultSharePrice
                )
            );
            assertEq(
                output.shareAdjustmentDelta,
                int256(
                    input.shareReservesDelta.mulDown(input.closeVaultSharePrice)
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
                input.openVaultSharePrice,
                input.closeVaultSharePrice,
                false
            );
            // NOTE: share proceeds aren't scaled
            assertEq(output.shareProceeds, input.shareProceeds);
            assertEq(
                output.shareReservesDelta,
                input.shareReservesDelta.mulDivDown(
                    input.closeVaultSharePrice,
                    input.openVaultSharePrice
                )
            );
            assertEq(
                output.shareCurveDelta,
                input.shareCurveDelta.mulDivDown(
                    input.closeVaultSharePrice,
                    input.openVaultSharePrice
                )
            );
            assertEq(
                output.totalGovernanceFee,
                input.totalGovernanceFee.mulDivDown(
                    input.closeVaultSharePrice,
                    input.openVaultSharePrice
                )
            );
            assertEq(
                output.shareAdjustmentDelta,
                int256(
                    input.shareReservesDelta.mulDown(input.closeVaultSharePrice)
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
        deploy(alice, fixedRate, 0, 0, 0, 0);

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
        deploy(alice, fixedRate, 0, 0, 0, 0);

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

        // This is an edge case where the present value couldn't be calculated
        // due to a tiny net curve trade.
        _test__calculateMaxLong(
            3988,
            370950184595018764582435593,
            10660,
            999000409571,
            1000000000012659
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
        deploy(alice, fixedRate, 0, 0, 0, 0);

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
        IHyperdrive.PoolConfig memory config = hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
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
                vaultSharePrice: info.vaultSharePrice,
                initialVaultSharePrice: config.initialVaultSharePrice,
                minimumShareReserves: config.minimumShareReserves,
                curveFee: config.fees.curve,
                flatFee: config.fees.flat,
                governanceLPFee: config.fees.governanceLP
            }),
            hyperdrive.getCheckpointExposure(hyperdrive.latestCheckpoint()),
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
        contribution = contribution.normalizeToRange(10_000e18, 500_000_000e18);
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
        contribution = contribution.normalizeToRange(10_000e18, 500_000_000e18);
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
        contribution = contribution.normalizeToRange(10_000e18, 500_000_000e18);
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
        IHyperdrive.PoolConfig memory config = hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
        uint256 maxShort = HyperdriveUtils.calculateMaxShort(
            HyperdriveUtils.MaxTradeParams({
                shareReserves: info.shareReserves,
                shareAdjustment: info.shareAdjustment,
                bondReserves: info.bondReserves,
                longsOutstanding: info.longsOutstanding,
                longExposure: info.longExposure,
                timeStretch: config.timeStretch,
                vaultSharePrice: info.vaultSharePrice,
                initialVaultSharePrice: config.initialVaultSharePrice,
                minimumShareReserves: config.minimumShareReserves,
                curveFee: config.fees.curve,
                flatFee: config.fees.flat,
                governanceLPFee: config.fees.governanceLP
            }),
            hyperdrive.getCheckpointExposure(hyperdrive.latestCheckpoint()),
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

    function test__calculateShortProceedsUp() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // 0% interest - 5% margin released - 0% interest after close
        uint256 bondAmount = 1.05e18;
        uint256 shareAmount = 1e18;
        uint256 openVaultSharePrice = 1e18;
        uint256 closeVaultSharePrice = 1e18;
        uint256 vaultSharePrice = 1e18;
        uint256 flatFee = 0;
        uint256 shortProceeds = hyperdriveMath.calculateShortProceedsUp(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / vault_share_price = (0.05 + 0) / 1
        assertEq(shortProceeds, 0.05e18);

        // 5% interest - 5% margin released - 0% interest after close
        bondAmount = 1.05e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 1.05e18;
        vaultSharePrice = 1.05e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceedsUp(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / vault_share_price = (0.05 + 1.05 * 0.05) / 1.05
        assertApproxEqAbs(
            shortProceeds,
            (0.05e18 + bondAmount.mulDown(0.05e18)).divDown(vaultSharePrice),
            1
        );

        // 5% interest - 0% margin released - 0% interest after close
        bondAmount = 1e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 1.05e18;
        vaultSharePrice = 1.05e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceedsUp(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / vault_share_price = (0 + 1 * 0.05) / 1.05
        assertApproxEqAbs(
            shortProceeds,
            (bondAmount.mulDown(0.05e18)).divDown(vaultSharePrice),
            1
        );

        // 5% interest - 5% margin released - 10% interest after close
        bondAmount = 1.05e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 1.05e18;
        vaultSharePrice = 1.155e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceedsUp(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / vault_share_price = (0.05 + 1.05 * 0.05) / 1.155
        assertApproxEqAbs(
            shortProceeds,
            (0.05e18 + bondAmount.mulDown(0.05e18)).divDown(vaultSharePrice),
            2
        );

        // -10% interest - 5% margin released - 0% interest after close
        bondAmount = 1.05e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 0.9e18;
        vaultSharePrice = 0.9e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceedsUp(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        assertEq(shortProceeds, 0);

        // -10% interest - 5% margin released - 20% interest after close
        bondAmount = 1.05e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 0.9e18;
        vaultSharePrice = 1.08e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceedsUp(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        assertEq(shortProceeds, 0);

        // 5% interest - 0% margin released - 0% interest after close
        // 50% flatFee applied
        bondAmount = 1e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 1.05e18;
        vaultSharePrice = 1.05e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0.5e18;
        shortProceeds = hyperdriveMath.calculateShortProceedsUp(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / vault_share_price
        //            + (bondAmount * flatFee) / vault_share_price
        //          = (0 + 1 * 0.05) / 1.05 + (1 * 0.5) / 1.05
        assertApproxEqAbs(
            shortProceeds,
            (bondAmount.mulDown(0.05e18)).divDown(vaultSharePrice) +
                (bondAmount.mulDivDown(flatFee, vaultSharePrice)),
            2
        );

        // 5% interest - 5% margin released - 0% interest after close
        bondAmount = 1.05e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 1.05e18;
        vaultSharePrice = 1.05e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0.25e18;
        shortProceeds = hyperdriveMath.calculateShortProceedsUp(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / vault_share_price
        //            + (bondAmount * flatFee) / vault_share_price
        //          = ((0.05 + 1.05 * 0.05) / 1.05) + ((1 * 0.25) / 1.05)
        assertApproxEqAbs(
            shortProceeds,
            (0.05e18 + bondAmount.mulDown(0.05e18)).divDown(vaultSharePrice) +
                bondAmount.mulDivDown(flatFee, vaultSharePrice),
            1
        );
    }

    function test__calculateShortProceedsDown() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // 0% interest - 5% margin released - 0% interest after close
        uint256 bondAmount = 1.05e18;
        uint256 shareAmount = 1e18;
        uint256 openVaultSharePrice = 1e18;
        uint256 closeVaultSharePrice = 1e18;
        uint256 vaultSharePrice = 1e18;
        uint256 flatFee = 0;
        uint256 shortProceeds = hyperdriveMath.calculateShortProceedsDown(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / vault_share_price = (0.05 + 0) / 1
        assertEq(shortProceeds, 0.05e18);

        // 5% interest - 5% margin released - 0% interest after close
        bondAmount = 1.05e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 1.05e18;
        vaultSharePrice = 1.05e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceedsDown(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / vault_share_price = (0.05 + 1.05 * 0.05) / 1.05
        assertApproxEqAbs(
            shortProceeds,
            (0.05e18 + bondAmount.mulDown(0.05e18)).divDown(vaultSharePrice),
            1
        );

        // 5% interest - 0% margin released - 0% interest after close
        bondAmount = 1e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 1.05e18;
        vaultSharePrice = 1.05e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceedsDown(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / vault_share_price = (0 + 1 * 0.05) / 1.05
        assertApproxEqAbs(
            shortProceeds,
            (bondAmount.mulDown(0.05e18)).divDown(vaultSharePrice),
            1
        );

        // 5% interest - 5% margin released - 10% interest after close
        bondAmount = 1.05e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 1.05e18;
        vaultSharePrice = 1.155e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceedsDown(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / vault_share_price = (0.05 + 1.05 * 0.05) / 1.155
        assertApproxEqAbs(
            shortProceeds,
            (0.05e18 + bondAmount.mulDown(0.05e18)).divDown(vaultSharePrice),
            1
        );

        // -10% interest - 5% margin released - 0% interest after close
        bondAmount = 1.05e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 0.9e18;
        vaultSharePrice = 0.9e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceedsDown(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        assertEq(shortProceeds, 0);

        // -10% interest - 5% margin released - 20% interest after close
        bondAmount = 1.05e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 0.9e18;
        vaultSharePrice = 1.08e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0;
        shortProceeds = hyperdriveMath.calculateShortProceedsDown(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        assertEq(shortProceeds, 0);

        // 5% interest - 0% margin released - 0% interest after close
        // 50% flatFee applied
        bondAmount = 1e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 1.05e18;
        vaultSharePrice = 1.05e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0.5e18;
        shortProceeds = hyperdriveMath.calculateShortProceedsDown(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / vault_share_price
        //            + (bondAmount * flatFee) / vault_share_price
        //          = (0 + 1 * 0.05) / 1.05 + (1 * 0.5) / 1.05
        assertApproxEqAbs(
            shortProceeds,
            (bondAmount.mulDown(0.05e18)).divDown(vaultSharePrice) +
                (bondAmount.mulDivDown(flatFee, vaultSharePrice)),
            1
        );

        // 5% interest - 5% margin released - 0% interest after close
        bondAmount = 1.05e18;
        openVaultSharePrice = 1e18;
        closeVaultSharePrice = 1.05e18;
        vaultSharePrice = 1.05e18;
        shareAmount = uint256(1e18).divDown(vaultSharePrice);
        flatFee = 0.25e18;
        shortProceeds = hyperdriveMath.calculateShortProceedsDown(
            bondAmount,
            shareAmount,
            openVaultSharePrice,
            closeVaultSharePrice,
            vaultSharePrice,
            flatFee
        );
        // proceeds = (margin + interest) / vault_share_price
        //            + (bondAmount * flatFee) / vault_share_price
        //          = ((0.05 + 1.05 * 0.05) / 1.05) + ((1 * 0.25) / 1.05)
        assertApproxEqAbs(
            shortProceeds,
            (0.05e18 + bondAmount.mulDown(0.05e18)).divDown(vaultSharePrice) +
                bondAmount.mulDivDown(flatFee, vaultSharePrice),
            1
        );
    }

    function test__calculateTimeRemainingScaledAndUnscaled(
        uint256 maturityTime
    ) external view {
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
}
