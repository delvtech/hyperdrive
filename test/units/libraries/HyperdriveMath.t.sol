// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { ERC20PresetFixedSupply } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import { Test } from "forge-std/Test.sol";
import { ForwarderFactory } from "contracts/src/ForwarderFactory.sol";
import { MockHyperdriveMath } from "contracts/test/MockHyperdriveMath.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";

contract HyperdriveMathTest is Test {
    using FixedPointMath for uint256;

    function setUp() public {}

    function test__calcSpotPrice() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        assertEq(
            hyperdriveMath.calculateSpotPrice(
                1 ether, // shareReserves
                1 ether, // bondReserves
                1 ether, // initalSharePrice
                1 ether, // timeRemaining
                1 ether // timeStretch
            ),
            1 ether // 1.0 spot price
        );

        assertApproxEqAbs(
            hyperdriveMath.calculateSpotPrice(
                1.1 ether, // shareReserves
                1 ether, // bondReserves
                1 ether, // initalSharePrice
                1 ether, // timeRemaining
                1 ether // timeStretch
            ),
            1.1 ether, // 1.1 spot price
            1 wei
        );
    }

    function test__calcAPRFromReserves() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        // equal reserves should make 0% APR
        assertEq(
            hyperdriveMath.calculateAPRFromReserves(
                1 ether, // shareReserves
                1 ether, // bondReserves
                1 ether, // initalSharePrice
                365 days, // positionDuration
                1 ether // timeStretch
            ),
            0 // 0% APR
        );

        // target a 10% APR
        assertApproxEqAbs(
            hyperdriveMath.calculateAPRFromReserves(
                1 ether, // shareReserves
                1.1 ether, // bondReserves
                1 ether, // initalSharePrice
                365 days, // positionDuration
                1 ether // timeStretch
            ),
            0.10 ether, // 10% APR
            2 wei // calculation rounds up 2 wei for some reason
        );
    }

    function test__calculateInitialBondReserves() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test .1% APR
        uint256 shareReserves = 500_000_000 ether;
        uint256 sharePrice = 1 ether;
        uint256 initialSharePrice = 1 ether;
        uint256 apr = 0.001 ether;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            1109.3438508425959e18
        );
        uint256 bondReserves = 2 *
            hyperdriveMath.calculateInitialBondReserves(
                shareReserves,
                sharePrice,
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            ) +
            shareReserves;
        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 20 wei);

        // Test 1% APR
        apr = 0.01 ether;
        timeStretch = FixedPointMath.ONE_18.divDown(110.93438508425959e18);
        bondReserves =
            2 *
            hyperdriveMath.calculateInitialBondReserves(
                shareReserves,
                sharePrice,
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            ) +
            shareReserves;
        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 1 wei);

        // Test 5% APR
        apr = 0.05 ether;
        timeStretch = FixedPointMath.ONE_18.divDown(22.186877016851916266e18);
        bondReserves =
            2 *
            hyperdriveMath.calculateInitialBondReserves(
                shareReserves,
                sharePrice,
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            ) +
            shareReserves;
        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 1 wei);

        // Test 25% APR
        apr = 0.25 ether;
        timeStretch = FixedPointMath.ONE_18.divDown(4.437375403370384e18);
        bondReserves =
            2 *
            hyperdriveMath.calculateInitialBondReserves(
                shareReserves,
                sharePrice,
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            ) +
            shareReserves;
        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 0 wei);

        // Test 50% APR
        apr = 0.50 ether;
        timeStretch = FixedPointMath.ONE_18.divDown(2.218687701685192e18);
        bondReserves =
            2 *
            hyperdriveMath.calculateInitialBondReserves(
                shareReserves,
                sharePrice,
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            ) +
            shareReserves;
        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 1 wei);

        // Test 100% APR
        apr = 1 ether;
        timeStretch = FixedPointMath.ONE_18.divDown(1.109343850842596e18);
        bondReserves =
            2 *
            hyperdriveMath.calculateInitialBondReserves(
                shareReserves,
                sharePrice,
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            ) +
            shareReserves;
        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 4 wei);
    }

    function test__calculateOpenLong() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test open long at 1% APR, No backdating
        uint256 shareReserves = 500_000_000 ether;
        uint256 bondReserves = 2 *
            503_926_401.456553339958190918 ether +
            shareReserves;
        uint256 initialSharePrice = 1 ether;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
        uint256 expectedAPR = 0.882004326279808182 ether;
        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 bondProceeds
        ) = hyperdriveMath.calculateOpenLong(
                shareReserves,
                bondReserves,
                50_000_000 ether, // amountIn
                FixedPointMath.ONE_18,
                timeStretch,
                1 ether, // sharePrice
                initialSharePrice
            );
        // verify that the flat part is zero
        assertEq(bondReservesDelta, bondProceeds);
        bondReserves -= bondReservesDelta;
        shareReserves += shareReservesDelta;
        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        // verify that the resulting APR is correct
        assertApproxEqAbs(result, expectedAPR.divDown(100e18), 3e12);
    }

    function test__calculateCloseLongBeforeMaturity() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test closing the long halfway thru the term that was opened at 1% APR, No backdating
        uint256 shareReserves = 550_000_000 ether;
        uint256 bondReserves = 2 *
            453_456_134.637519001960754395 ether +
            shareReserves;
        uint256 positionDuration = 365 days;
        uint256 normalizedTimeRemaining = 0.5e18;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
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
                1 ether,
                1 ether
            );
        // verify that the poolBondDelta equals the amountIn/2
        assertEq(bondReservesDelta, amountIn.mulDown(normalizedTimeRemaining));
        shareReserves -= shareReservesDelta;
        bondReserves += bondReservesDelta;
        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            1 ether,
            positionDuration,
            timeStretch
        );
        // verify that the resulting APR is correct
        assertApproxEqAbs(result, expectedAPR.divDown(100e18), 4e12);
    }

    function test__calculateCloseLongAtMaturity() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test closing the long at maturity that was opened at 1% APR, No backdating
        uint256 shareReserves = 550_000_000 ether;
        uint256 bondReserves = 2 *
            453_456_134.637519001960754395 ether +
            shareReserves;
        uint256 normalizedTimeRemaining = 0;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
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
                1 ether,
                1 ether
            );
        // verify that the curve part is zero
        assertEq(shareReservesDelta, 0);
        assertEq(bondReservesDelta, 0);
        // verify that the flat part is the amountIn * sharePrice (sharePrice = 1)
        assertEq(shareProceeds, amountIn);
    }

    function test__calculateCloseLongAtMaturityNegativeInterest() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test closing the long at maturity that was opened at 1% APR, no
        // backdating. Negative interest accrued over the period and the share
        // price didn't change after closing.
        uint256 shareReserves = 550_000_000 ether;
        uint256 bondReserves = 2 *
            453_456_134.637519001960754395 ether +
            shareReserves;
        uint256 normalizedTimeRemaining = 0;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
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
                0.8 ether,
                0.8 ether,
                1 ether
            );
        // verify that the curve part is zero
        assertEq(shareReservesDelta, 0);
        assertEq(bondReservesDelta, 0);
        // verify that the flat part is the amountIn * (closeSharePrice / sharePrice)
        assertApproxEqAbs(
            shareProceeds,
            amountIn.mulDown(0.8 ether).divDown(0.8 ether),
            1
        );

        // Test closing the long at maturity that was opened at 1% APR, no
        // backdating. Negative interest accrued over the period and the share
        // price increased after.
        (shareReservesDelta, bondReservesDelta, shareProceeds) = hyperdriveMath
            .calculateCloseLong(
                shareReserves,
                bondReserves,
                amountIn,
                normalizedTimeRemaining,
                timeStretch,
                0.8 ether,
                1.2 ether,
                1 ether
            );
        // verify that the curve part is zero
        assertEq(shareReservesDelta, 0);
        assertEq(bondReservesDelta, 0);
        // verify that the flat part is the amountIn * (closeSharePrice / sharePrice)
        assertApproxEqAbs(
            shareProceeds,
            amountIn.mulUp(0.8 ether).divDown(1.2 ether),
            1
        );
    }

    function test__calculateOpenShortTrade() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test open long at 1% APR, No backdating
        uint256 shareReserves = 500_000_000 ether;
        uint256 bondReserves = 2 *
            503_926_401.456553339958190918 ether +
            shareReserves;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
        uint256 expectedAPR = 1.1246406058180446 ether;
        {
            uint256 amountIn = 50_000_000 ether;
            (
                uint256 shareReservesDelta,
                uint256 bondReservesDelta,
                uint256 shareProceeds
            ) = hyperdriveMath.calculateOpenShortTrade(
                    shareReserves,
                    bondReserves,
                    amountIn,
                    FixedPointMath.ONE_18,
                    timeStretch,
                    1 ether,
                    1 ether
                );
            // verify that the flat part is zero
            assertEq(shareProceeds, shareReservesDelta);
            bondReserves += bondReservesDelta;
            shareReserves -= shareReservesDelta;
        }
        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            1 ether,
            positionDuration,
            timeStretch
        );
        // verify that the resulting APR is correct
        assertApproxEqAbs(result, expectedAPR.divDown(100e18), 6e12);
    }

    function test__calculateCloseShortAtMaturity() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test closing the long at maturity that was opened at 1% APR, No backdating
        uint256 shareReserves = 450_000_000 ether;
        uint256 bondReserves = 2 *
            554_396_668.275587677955627441 ether +
            shareReserves;
        uint256 normalizedTimeRemaining = 0;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
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

    function test__calculateCloseShortBeforeMaturity() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test closing the long at maturity that was opened at 1% APR, No backdating
        uint256 shareReserves = 450_000_000 ether;
        uint256 bondReserves = 2 *
            554_396_668.275587677955627441 ether +
            shareReserves;
        uint256 positionDuration = 365 days;
        uint256 normalizedTimeRemaining = 0.5e18;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
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
        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            1 ether,
            positionDuration,
            timeStretch
        );
        // verify that the resulting APR is correct
        assertApproxEqAbs(result, expectedAPR.divDown(100e18), 3e12);
    }

    function test__calculateShortProceeds() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // 0% interest - 5% margin released - 0% interest after close
        uint256 bondAmount = 1.05e18;
        uint256 shareAmount = 1e18;
        uint256 openSharePrice = 1e18;
        uint256 closeSharePrice = 1e18;
        uint256 sharePrice = 1e18;
        uint256 shortProceeds = hyperdriveMath.calculateShortProceeds(
            bondAmount,
            shareAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice
        );
        // proceeds = (margin + interest) / share_price = (0.05 + 0) / 1
        assertEq(shortProceeds, 0.05e18);

        // 5% interest - 5% margin released - 0% interest after close
        bondAmount = 1.05e18;
        openSharePrice = 1e18;
        closeSharePrice = 1.05e18;
        sharePrice = 1.05e18;
        shareAmount = uint256(1e18).divDown(sharePrice);
        shortProceeds = hyperdriveMath.calculateShortProceeds(
            bondAmount,
            shareAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice
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
        shortProceeds = hyperdriveMath.calculateShortProceeds(
            bondAmount,
            shareAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice
        );
        // proceeds = (margin + interest) / share_price = (0 + 1 * 0.05) / 1.05
        assertApproxEqAbs(
            shortProceeds,
            (bondAmount.mulDown(0.05e18)).divDown(sharePrice),
            1
        );

        // FIXME: This currently fails and needs to be fixed.
        //
        // 5% interest - 5% margin released - 10% interest after close
        // bondAmount = 1.05e18;
        // openSharePrice = 1e18;
        // closeSharePrice = 1.05e18;
        // sharePrice = 1.155e18;
        // shareAmount = uint256(1e18).divDown(sharePrice);
        // shortProceeds = hyperdriveMath.calculateShortProceeds(
        //     bondAmount,
        //     shareAmount,
        //     openSharePrice,
        //     closeSharePrice,
        //     sharePrice
        // );
        // // proceeds = (margin + interest) / share_price = (0.05 + 1.05 * 0.05) / 1.155
        // assertEq(
        //     shortProceeds,
        //     (0.05e18 + bondAmount.mulDown(0.05e18)).divDown(sharePrice)
        // );

        // -10% interest - 5% margin released - 0% interest after close
        bondAmount = 1.05e18;
        openSharePrice = 1e18;
        closeSharePrice = 0.9e18;
        sharePrice = 0.9e18;
        shareAmount = uint256(1e18).divDown(sharePrice);
        shortProceeds = hyperdriveMath.calculateShortProceeds(
            bondAmount,
            shareAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice
        );
        assertEq(shortProceeds, 0);

        // FIXME: This currently fails and needs to be fixed.
        //
        // -10% interest - 5% margin released - 20% interest after close
        // bondAmount = 1.05e18;
        // openSharePrice = 1e18;
        // closeSharePrice = 0.9e18;
        // sharePrice = 1.08e18;
        // shareAmount = uint256(1e18).divDown(sharePrice);
        // shortProceeds = hyperdriveMath.calculateShortProceeds(
        //     bondAmount,
        //     shareAmount,
        //     openSharePrice,
        //     closeSharePrice,
        //     sharePrice
        // );
        // assertEq(shortProceeds, 0);
    }

    function test__calculateShortInterest() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // 0% interest - 0% interest after close
        uint256 bondAmount = 1.05e18;
        uint256 openSharePrice = 1e18;
        uint256 closeSharePrice = 1e18;
        uint256 sharePrice = 1e18;
        uint256 shortInterest = hyperdriveMath.calculateShortInterest(
            bondAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice
        );
        // proceeds = interest / share_price = 0 / 1
        assertEq(shortInterest, 0);

        // 5% interest - 0% interest after close
        bondAmount = 1.05e18;
        openSharePrice = 1e18;
        closeSharePrice = 1.05e18;
        sharePrice = 1.05e18;
        shortInterest = hyperdriveMath.calculateShortInterest(
            bondAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice
        );
        // proceeds = interest / share_price = (1.05 * 0.05) / 1.05
        assertApproxEqAbs(
            shortInterest,
            bondAmount.mulDivDown(0.05e18, sharePrice),
            1
        );

        // 5% interest - 10% interest after close
        bondAmount = 1.05e18;
        openSharePrice = 1e18;
        closeSharePrice = 1.05e18;
        sharePrice = 1.155e18;
        shortInterest = hyperdriveMath.calculateShortInterest(
            bondAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice
        );
        // proceeds = interest / share_price = (1.05 * 0.05) / 1.155
        assertEq(shortInterest, bondAmount.mulDivDown(0.05e18, sharePrice));

        // -10% interest - 0% interest after close
        bondAmount = 1.05e18;
        openSharePrice = 1e18;
        closeSharePrice = 0.9e18;
        sharePrice = 0.9e18;
        shortInterest = hyperdriveMath.calculateShortInterest(
            bondAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice
        );
        assertEq(shortInterest, 0);

        // -10% interest - 20% interest after close
        bondAmount = 1.05e18;
        openSharePrice = 1e18;
        closeSharePrice = 0.9e18;
        sharePrice = 1.08e18;
        shortInterest = hyperdriveMath.calculateShortInterest(
            bondAmount,
            openSharePrice,
            closeSharePrice,
            sharePrice
        );
        assertEq(shortInterest, 0);
    }

    function test__calculateBaseVolume() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        uint256 baseVolume = hyperdriveMath.calculateBaseVolume(
            5 ether, // baseAmount
            2 ether, // bondAmount
            0.5e18 // timeRemaining
        );
        // (5 - (1-.5) * 2)/0.5 = (5 - 1)/0.5 = 8
        assertEq(baseVolume, 8 ether);
    }

    function test__calculateBaseVolumeWithZeroTimeRemaining() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        uint256 baseVolume = hyperdriveMath.calculateBaseVolume(
            1 ether, // baseAmount
            1 ether, // bondAmount
            0 // timeRemaining
        );
        assertEq(baseVolume, 0);
    }

    function test__calculateLpAllocationAdjustment() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        uint256 lpAllocationAdjustment = hyperdriveMath
            .calculateLpAllocationAdjustment(
                5 ether, // positionsOutstanding
                10 ether, // baseVolume
                .5e18, // averageTimeRemaining
                3.75 ether // sharePrice
            );
        // baseAdjustment = .5 * 10 + (1 - .5) * 5 = 7.5
        // adjustment = baseAdjustment / 3.75 = 2
        assertEq(lpAllocationAdjustment, 2 ether);
    }

    function test__calculateOutForLpSharesIn() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        (uint256 out, , ) = hyperdriveMath.calculateOutForLpSharesIn(
            100 ether, //_shares
            1000 ether, //_shareReserves
            1000 ether, //_lpTotalSupply
            0 ether, // _longsOutstanding
            0 ether, //_shortsOutstanding
            1.5 ether //_sharePrice
        );
        // (1000 - 0 / 1.5) * (100 / 1000) = 100
        assertEq(out, 100 ether);
    }

    function test_calculateFeesOutGivenBondsIn() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 totalGovernanceFee
        ) = hyperdriveMath.calculateFeesOutGivenBondsIn(
                1 ether, // bondIn
                1 ether, // timeRemaining
                0.9 ether, // spotPrice
                1 ether, // sharePrice
                0.1e18, // curveFee
                0.1e18, // flatFee
                0.5e18 // governanceFee
            );
        // curve fee = ((1 - p) * phi_curve * d_y * t) / c
        // ((1-.9)*.1*1*1)/1 = .01
        assertEq(totalCurveFee + totalFlatFee, .01 ether);
        assertEq(totalGovernanceFee, .005 ether);

        (totalCurveFee, totalFlatFee, totalGovernanceFee) = hyperdriveMath
            .calculateFeesOutGivenBondsIn(
                1 ether, // amountIn
                0, // timeRemaining
                0.9 ether, // spotPrice
                1 ether, // sharePrice
                0.1e18, // curveFee
                0.1e18, // flatFee
                0.5e18 // governanceFee
            );
        assertEq(totalCurveFee + totalFlatFee, 0.1 ether);
        assertEq(totalGovernanceFee, 0.05 ether);
    }
}
