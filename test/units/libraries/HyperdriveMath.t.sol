// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20PresetFixedSupply } from "openzeppelin-contracts/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { MockHyperdriveMath } from "contracts/test/MockHyperdriveMath.sol";
import { IMockHyperdrive } from "test/mocks/MockHyperdrive.sol";
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
            hyperdriveMath.calculateAPRFromReserves(
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
            hyperdriveMath.calculateAPRFromReserves(
                1 ether, // shareReserves
                1.1 ether, // bondReserves
                1 ether, // initialSharePrice
                365 days, // positionDuration
                1 ether // timeStretch
            ),
            0.10 ether, // 10% APR
            2 wei // calculation rounds up 2 wei for some reason
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
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            1109.3438508425959e18
        );
        uint256 bondReserves = hyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
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
        bondReserves = hyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
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
        bondReserves = hyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
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
        bondReserves = hyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
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
        bondReserves = hyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
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
        bondReserves = hyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        result = hyperdriveMath.calculateAPRFromReserves(
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
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
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

    function test__calculateCloseLongAtMaturity() external {
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
                1 ether,
                1 ether
            );
        // verify that the curve part is zero
        assertEq(shareReservesDelta, 0);
        assertEq(bondReservesDelta, 0);
        // verify that the flat part is the amountIn * sharePrice (sharePrice = 1)
        assertEq(shareProceeds, amountIn);
    }

    function test__calculateCloseLongAtMaturityNegativeInterest() external {
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
                1 ether,
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
                1 ether,
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

    function test__calculateOpenShort() external {
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

    function test__calculateCloseShortAtMaturity() external {
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

    // TODO: Fix this test
    // function test__calculateMaxLong(
    //     uint256 fixedRate,
    //     uint256 contribution,
    //     uint256 initialLongAmount,
    //     uint256 initialShortAmount,
    //     uint256 finalLongAmount
    // ) external {
    //     _test__calculateMaxLong(
    //         fixedRate,
    //         contribution,
    //         initialLongAmount,
    //         initialShortAmount,
    //         finalLongAmount
    //     );
    // }

    function test__calculateClosePositionExposure() external {
        {
            uint256 _positionExposure = 500e18;
            uint256 _baseReservesDelta = 100e18;
            uint256 _bondReservesDelta = 100e18;
            uint256 _baseUserDelta = 200e18;
            uint256 _checkpointPositions = 0;
            uint128 delta = HyperdriveMath.calculateClosePositionExposure(
                _positionExposure,
                _bondReservesDelta,
                _baseReservesDelta,
                _bondReservesDelta,
                _baseUserDelta,
                _checkpointPositions
            );

            // delta should be equal to _positionExposure bc there are 0 checkpoint positions
            assertEq(delta, 500e18);
        }

        // Flat + Curve  Test
        {
            uint256 _positionExposure = 500e18;
            uint256 _bondProceeds = 100e18;
            uint256 _baseReservesDelta = 10e18;
            uint256 _bondReservesDelta = 100e18;
            uint256 _baseUserDelta = 200e18;
            uint256 _checkpointPositions = 10e18;
            uint128 delta = HyperdriveMath.calculateClosePositionExposure(
                _positionExposure,
                _bondProceeds,
                _baseReservesDelta,
                _bondReservesDelta,
                _baseUserDelta,
                _checkpointPositions
            );
            uint256 flatPlusCurveDelta = _baseUserDelta -
                _baseReservesDelta +
                _bondReservesDelta -
                _baseReservesDelta;
            // delta should be equal to flatPlusCurveDelta + _bondProceeds bc
            // _positionExposure >= flatPlusCurveDelta + _bondProceeds
            assertEq(delta, flatPlusCurveDelta + _bondProceeds);
        }

        {
            uint256 _positionExposure = 1e18;
            uint256 _baseReservesDelta = 100e18;
            uint256 _bondReservesDelta = 100e18;
            uint256 _baseUserDelta = 200e18;
            uint256 _checkpointPositions = 10e18;
            uint128 delta = HyperdriveMath.calculateClosePositionExposure(
                _positionExposure,
                _bondReservesDelta,
                _baseReservesDelta,
                _bondReservesDelta,
                _baseUserDelta,
                _checkpointPositions
            );

            // delta should be equal to _positionExposure bc 
            // _positionExposure < flatPlusCurveDelta + _bondProceeds
            assertEq(delta, _positionExposure);
        }
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

    function _test__calculateMaxLong(
        uint256 fixedRate,
        uint256 contribution,
        uint256 initialLongAmount,
        uint256 initialShortAmount,
        uint256 finalLongAmount
    ) internal {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Deploy Hyperdrive.
        fixedRate = fixedRate.normalizeToRange(0.001e18, 0.5e18);
        deploy(alice, fixedRate, 0, 0, 0);

        // Initialize the Hyperdrive pool.
        contribution = contribution.normalizeToRange(1_000e18, 500_000_000e18);
        initialize(alice, fixedRate, contribution);

        // Open a long and a short. This sets the long buffer to a non-trivial
        // value which stress tests the max long function.
        initialLongAmount = initialLongAmount.normalizeToRange(
            0.0001e18,
            hyperdrive.calculateMaxLong() / 2
        );
        openLong(bob, initialLongAmount);
        initialShortAmount = initialShortAmount.normalizeToRange(
            0.0001e18,
            hyperdrive.calculateMaxShort() / 2
        );
        openShort(bob, initialShortAmount);

        // Open the maximum long on Hyperdrive.
        IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory config = hyperdrive.getPoolConfig();
        uint256 maxIterations = 7;
        if (fixedRate > 0.15e18) {
            maxIterations += 5;
        }
        if (fixedRate > 0.35e18) {
            maxIterations += 5;
        }
        (uint256 maxLong, ) = hyperdriveMath.calculateMaxLong(
            HyperdriveMath.MaxTradeParams({
                shareReserves: info.shareReserves,
                bondReserves: info.bondReserves,
                longsOutstanding: info.longsOutstanding,
                timeStretch: config.timeStretch,
                sharePrice: info.sharePrice,
                initialSharePrice: config.initialSharePrice,
                minimumShareReserves: config.minimumShareReserves
            }),
            maxIterations
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, maxLong);

        // Ensure that opening another long fails.
        vm.stopPrank();
        vm.startPrank(bob);
        finalLongAmount = finalLongAmount.normalizeToRange(
            0.01e18,
            100_000_000e18
        );
        baseToken.mint(bob, finalLongAmount);
        baseToken.approve(address(hyperdrive), finalLongAmount);
        vm.expectRevert();
        hyperdrive.openLong(finalLongAmount, 0, bob, true);

        // Ensure that the long can be closed.
        closeLong(bob, maturityTime, longAmount);
    }

    // TODO: Fix this test
    // function test__calculateMaxShort(
    //     uint256 fixedRate,
    //     uint256 contribution,
    //     uint256 initialLongAmount,
    //     uint256 initialShortAmount,
    //     uint256 finalShortAmount
    // ) external {
    //     // NOTE: Coverage only works if I initialize the fixture in the test function
    //     MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

    //     // Initialize the Hyperdrive pool.
    //     contribution = contribution.normalizeToRange(1_000e18, 500_000_000e18);
    //     fixedRate = fixedRate.normalizeToRange(0.0001e18, 0.5e18);
    //     initialize(alice, fixedRate, contribution);

    //     // Open a long. This sets the long buffer to a non-trivial value which
    //     // stress tests the max long function.
    //     initialLongAmount = initialLongAmount.normalizeToRange(
    //         0.001e18,
    //         hyperdrive.calculateMaxLong() / 2
    //     );
    //     openLong(bob, initialLongAmount);
    //     initialShortAmount = initialShortAmount.normalizeToRange(
    //         0.0001e18,
    //         hyperdrive.calculateMaxShort() / 2
    //     );
    //     openShort(bob, initialShortAmount);

    //     // Open the maximum short on Hyperdrive.
    //     IHyperdrive.PoolInfo memory info = hyperdrive.getPoolInfo();
    //     IHyperdrive.PoolConfig memory config = hyperdrive.getPoolConfig();
    //     uint256 maxShort = hyperdriveMath.calculateMaxShort(
    //         HyperdriveMath.MaxTradeParams({
    //             shareReserves: info.shareReserves,
    //             bondReserves: info.bondReserves,
    //             longsOutstanding: info.longsOutstanding,
    //             timeStretch: config.timeStretch,
    //             sharePrice: info.sharePrice,
    //             initialSharePrice: config.initialSharePrice,
    //             minimumShareReserves: config.minimumShareReserves
    //         })
    //     );
    //     (uint256 maturityTime, ) = openShort(bob, maxShort);

    //     // Ensure that opening another short fails.
    //     vm.stopPrank();
    //     vm.startPrank(bob);
    //     finalShortAmount = finalShortAmount.normalizeToRange(
    //         0.00001e18,
    //         100_000_000e18
    //     );
    //     baseToken.mint(bob, finalShortAmount);
    //     baseToken.approve(address(hyperdrive), finalShortAmount);
    //     vm.expectRevert();
    //     hyperdrive.openShort(finalShortAmount, 0, bob, true);

    //     // Ensure that the short can be closed.
    //     closeShort(bob, maturityTime, maxShort);
    // }

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
                .calculateSharesOutGivenBondsIn(
                    params.shareReserves,
                    params.bondReserves,
                    params.longsOutstanding,
                    FixedPointMath.ONE_18 - params.timeStretch,
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
                .calculateSharesInGivenBondsOut(
                    params.shareReserves,
                    params.bondReserves,
                    params.shortsOutstanding,
                    FixedPointMath.ONE_18 - params.timeStretch,
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
                .calculateSharesInGivenBondsOut(
                    params.shareReserves,
                    params.bondReserves,
                    params.shortsOutstanding,
                    FixedPointMath.ONE_18 - params.timeStretch,
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
                .calculateSharesOutGivenBondsIn(
                    params.shareReserves,
                    params.bondReserves,
                    params.longsOutstanding,
                    FixedPointMath.ONE_18 - params.timeStretch,
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
                .calculateSharesInGivenBondsOut(
                    params.shareReserves,
                    params.bondReserves,
                    params.shortsOutstanding.mulDown(
                        params.shortAverageTimeRemaining
                    ) -
                        params.longsOutstanding.mulDown(
                            params.longAverageTimeRemaining
                        ),
                    FixedPointMath.ONE_18 - params.timeStretch,
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
                .calculateSharesOutGivenBondsIn(
                    params.shareReserves,
                    params.bondReserves,
                    params.longsOutstanding.mulDown(
                        params.longAverageTimeRemaining
                    ) -
                        params.shortsOutstanding.mulDown(
                            params.shortAverageTimeRemaining
                        ),
                    FixedPointMath.ONE_18 - params.timeStretch,
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
            (, uint256 maxCurveTrade) = YieldSpaceMath.calculateMaxBuy(
                params.shareReserves,
                params.bondReserves,
                FixedPointMath.ONE_18 - params.timeStretch,
                params.sharePrice,
                params.initialSharePrice
            );
            params.shareReserves += YieldSpaceMath
                .calculateSharesInGivenBondsOut(
                    params.shareReserves,
                    params.bondReserves,
                    maxCurveTrade,
                    FixedPointMath.ONE_18 - params.timeStretch,
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

        // complicate scenario with non-trivial minimum share reserves
        {
            HyperdriveMath.PresentValueParams memory params = HyperdriveMath
                .PresentValueParams({
                    shareReserves: 100_000e18,
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
            (, uint256 maxCurveTrade) = YieldSpaceMath.calculateMaxBuy(
                params.shareReserves,
                params.bondReserves,
                FixedPointMath.ONE_18 - params.timeStretch,
                params.sharePrice,
                params.initialSharePrice
            );
            params.shareReserves += YieldSpaceMath
                .calculateSharesInGivenBondsOut(
                    params.shareReserves,
                    params.bondReserves,
                    maxCurveTrade,
                    FixedPointMath.ONE_18 - params.timeStretch,
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

    function test__calculateShortInterest() external {
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
            .calculateTimeRemainingScaled(maturityTime * FixedPointMath.ONE_18);
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
        uint256 tau = FixedPointMath.ONE_18.mulDown(_timeStretch);
        uint256 interestFactor = (FixedPointMath.ONE_18 + _apr.mulDown(t)).pow(
            FixedPointMath.ONE_18.divDown(tau)
        );

        // bondReserves = mu * z * (1 + apr * t) ** (1 / tau)
        bondReserves = _initialSharePrice.mulDown(_shareReserves).mulDown(
            interestFactor
        );
        return bondReserves;
    }
}
