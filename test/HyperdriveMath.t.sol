// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { ERC20PresetFixedSupply } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import { Test } from "forge-std/Test.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";
import { MockHyperdriveMath } from "test/mocks/MockHyperdriveMath.sol";
import "contracts/libraries/FixedPointMath.sol";
import "forge-std/console2.sol";

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
                0 ether, // lpTotalSupply
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
                0 ether, // lpTotalSupply
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
                0 ether, // lpTotalSupply
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
                0 ether, // lpTotalSupply
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
        uint256 bondReserves = hyperdriveMath.calculateInitialBondReserves(
            shareReserves,
            sharePrice,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            shareReserves.add(bondReserves),
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
            sharePrice,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            shareReserves.add(bondReserves),
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
            sharePrice,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            shareReserves.add(bondReserves),
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
            sharePrice,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            shareReserves.add(bondReserves),
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
            sharePrice,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            shareReserves.add(bondReserves),
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
            sharePrice,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );
        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            shareReserves.add(bondReserves),
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 4 wei);
    }

    function test__calculateBondReserves() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test .1% APR with 5% drift in total supply
        uint256 shareReserves = 500_000_000 ether;
        uint256 bondReserves = 507_671_918.147567987442016602 ether;
        uint256 totalSupply = shareReserves.add(bondReserves).mulDown(.95e18);
        uint256 initialSharePrice = 1 ether;
        uint256 apr = 0.001 ether;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            1109.3438508425959e18
        );

        uint256 newBondReserves = hyperdriveMath.calculateBondReserves(
            shareReserves,
            shareReserves.add(bondReserves).mulDown(.95e18),
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );

        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            newBondReserves,
            totalSupply,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 1 wei);

        // Test .5% APR with 5% drift in total supply
        shareReserves = 500_000_000 ether;
        bondReserves = 505_999_427.633650124073028564 ether;
        totalSupply = shareReserves.add(bondReserves).mulDown(.95e18);
        initialSharePrice = 1 ether;
        apr = 0.005 ether;
        positionDuration = 365 days;
        timeStretch = FixedPointMath.ONE_18.divDown(221.86877016851918e18);

        newBondReserves = hyperdriveMath.calculateBondReserves(
            shareReserves,
            shareReserves.add(bondReserves).mulDown(.95e18),
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );

        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            newBondReserves,
            totalSupply,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 0);

        // Test 1% APR with 5% drift in total supply
        shareReserves = 500_000_000 ether;
        bondReserves = 503_926_401.456553339958190918 ether;
        totalSupply = shareReserves.add(bondReserves).mulDown(.95e18);
        initialSharePrice = 1 ether;
        apr = .01 ether;
        positionDuration = 365 days;
        timeStretch = FixedPointMath.ONE_18.divDown(110.93438508425959e18);

        newBondReserves = hyperdriveMath.calculateBondReserves(
            shareReserves,
            shareReserves.add(bondReserves).mulDown(.95e18),
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );

        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            newBondReserves,
            totalSupply,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 0);

        // Test 10% APR with 5% drift in total supply
        shareReserves = 500_000_000 ether;
        bondReserves = 469_659_754.230894804000854492 ether;
        totalSupply = shareReserves.add(bondReserves).mulDown(.95e18);
        initialSharePrice = 1 ether;
        apr = .1 ether;
        positionDuration = 365 days;
        timeStretch = FixedPointMath.ONE_18.divDown(11.093438508425958e18);

        newBondReserves = hyperdriveMath.calculateBondReserves(
            shareReserves,
            shareReserves.add(bondReserves).mulDown(.95e18),
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );

        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            newBondReserves,
            totalSupply,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 1 wei);

        // Test 50% APR with 5% drift in total supply
        shareReserves = 500_000_000 ether;
        bondReserves = 364_655_142.534339368343353271 ether;
        totalSupply = shareReserves.add(bondReserves).mulDown(.95e18);
        initialSharePrice = 1 ether;
        apr = .5 ether;
        positionDuration = 365 days;
        timeStretch = FixedPointMath.ONE_18.divDown(2.218687701685192e18);

        newBondReserves = hyperdriveMath.calculateBondReserves(
            shareReserves,
            totalSupply,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );

        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            newBondReserves,
            totalSupply,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 1 wei);

        // Test 100% APR with 5% drift in total supply
        shareReserves = 500_000_000 ether;
        bondReserves = 289_368_753.268716454505920410 ether;
        totalSupply = shareReserves.add(bondReserves).mulDown(.95e18);
        initialSharePrice = 1 ether;
        apr = 1 ether;
        positionDuration = 365 days;
        timeStretch = FixedPointMath.ONE_18.divDown(1.109343850842596e18);

        newBondReserves = hyperdriveMath.calculateBondReserves(
            shareReserves,
            totalSupply,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );

        result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            newBondReserves,
            totalSupply,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        assertApproxEqAbs(result, apr, 0 wei);
    }

    function test__calculateOpenLong() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test open long at 1% APR, No backdating
        uint256 shareReserves = 500_000_000 ether;
        uint256 bondReserves = 503_926_401.456553339958190918 ether;
        uint256 totalSupply = shareReserves.add(bondReserves);
        uint256 sharePrice = 1 ether;
        uint256 initialSharePrice = 1 ether;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
        uint256 amountIn = 50_000_000 ether;
        uint256 expectedAPR = 0.882004326279808182 ether;
        (uint256 poolBondDelta, uint256 userDelta) = hyperdriveMath
            .calculateOpenLong(
                shareReserves,
                bondReserves,
                totalSupply,
                amountIn,
                FixedPointMath.ONE_18,
                timeStretch,
                sharePrice,
                initialSharePrice
            );
        // verify that the flat part is zero
        assertEq(poolBondDelta, userDelta);
        bondReserves -= poolBondDelta;
        shareReserves += amountIn;
        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            totalSupply,
            initialSharePrice,
            positionDuration,
            timeStretch
        );
        // verify that the resulting APR is correct
        assertApproxEqAbs(result, expectedAPR.divDown(100e18), 3e12);
    }

    function test__calculateCloseLongAtMaturity() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test closing the long at maturity that was opened at 1% APR, No backdating
        uint256 shareReserves = 550_000_000 ether;
        uint256 bondReserves = 453_456_134.637519001960754395 ether;
        uint256 totalSupply = shareReserves.add(bondReserves);
        uint256 sharePrice = 1 ether;
        uint256 initialSharePrice = 1 ether;
        uint256 positionDuration = 365 days;
        uint256 normalizedTimeRemaining = 0;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
        uint256 amountIn = 503_926_401.456553339958190918 ether -
            453_456_134.637519001960754395 ether;
        uint256 expectedAPR = 0.969865355289938558 ether;
        (uint256 poolBondDelta, ) = hyperdriveMath.calculateCloseLong(
            shareReserves,
            bondReserves,
            totalSupply,
            amountIn,
            normalizedTimeRemaining,
            timeStretch,
            sharePrice,
            initialSharePrice
        );
        // verify that the curve part is zero
        assertEq(poolBondDelta, 0);
        shareReserves -= amountIn;
        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            totalSupply,
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
        uint256 bondReserves = 453_456_134.637519001960754395 ether;
        uint256 totalSupply = shareReserves.add(bondReserves);
        uint256 positionDuration = 365 days;
        uint256 normalizedTimeRemaining = 0.5e18;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
        uint256 amountIn = 503_926_401.456553339958190918 ether -
            453_456_134.637519001960754395 ether;
        uint256 expectedAPR = 0.985076602986273420 ether;
        (uint256 poolBondDelta, uint256 userDelta) = hyperdriveMath
            .calculateCloseLong(
                shareReserves,
                bondReserves,
                totalSupply,
                amountIn,
                normalizedTimeRemaining,
                timeStretch,
                1 ether,
                1 ether
            );
        // verify that the poolBondDelta equals the amountIn/2
        assertEq(poolBondDelta, amountIn.mulDown(normalizedTimeRemaining));
        shareReserves -= userDelta;
        bondReserves += poolBondDelta;
        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            totalSupply,
            1 ether,
            positionDuration,
            timeStretch
        );
        // verify that the resulting APR is correct
        assertApproxEqAbs(result, expectedAPR.divDown(100e18), 4e12);
    }

    function test__calculateOpenShort() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test open long at 1% APR, No backdating
        uint256 shareReserves = 500_000_000 ether;
        uint256 bondReserves = 503_926_401.456553339958190918 ether;
        uint256 totalSupply = shareReserves.add(bondReserves);
        uint256 sharePrice = 1 ether;
        uint256 initialSharePrice = 1 ether;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
        uint256 amountIn = 50_000_000 ether;
        uint256 expectedAPR = 1.125979043589839357 ether;
        uint256 poolShareDelta = hyperdriveMath.calculateOpenShort(
            shareReserves,
            bondReserves,
            totalSupply,
            amountIn,
            FixedPointMath.ONE_18,
            timeStretch,
            sharePrice,
            initialSharePrice
        );
        // verify that the flat part is zero
        //assertEq(poolShareDelta);
        bondReserves += poolShareDelta;
        shareReserves -= amountIn;
        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            totalSupply,
            initialSharePrice,
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
        uint256 bondReserves = 554_396_668.275587677955627441 ether;
        uint256 totalSupply = shareReserves.add(bondReserves);
        uint256 positionDuration = 365 days;
        uint256 normalizedTimeRemaining = 0;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
        uint256 amountOut = 50_470_266.819034337997436523 ether;
        uint256 expectedAPR = 1.029123553254638335 ether;
        (uint256 poolBondDelta, ) = hyperdriveMath.calculateCloseShort(
            shareReserves,
            bondReserves,
            totalSupply,
            amountOut,
            normalizedTimeRemaining,
            timeStretch,
            1 ether,
            1 ether,
            0 ether,
            0 ether
        );
        // verify that the curve part is zero
        assertEq(poolBondDelta, 0);
        shareReserves += amountOut;
        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            totalSupply,
            1 ether,
            positionDuration,
            timeStretch
        );
        // verify that the resulting APR is correct
        assertApproxEqAbs(result, expectedAPR.divDown(100e18), 3e12);
    }

    function test__calculateCloseShortBeforeMaturity() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();

        // Test closing the long at maturity that was opened at 1% APR, No backdating
        uint256 shareReserves = 450_000_000 ether;
        uint256 bondReserves = 554_396_668.275587677955627441 ether;
        uint256 totalSupply = shareReserves.add(bondReserves);
        uint256 positionDuration = 365 days;
        uint256 normalizedTimeRemaining = 0.5e18;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
        uint256 amountOut = 50_470_266.819034337997436523 ether;
        uint256 expectedAPR = 1.014782319047301762 ether;
        (uint256 poolBondDelta, uint256 userDelta) = hyperdriveMath
            .calculateCloseShort(
                shareReserves,
                bondReserves,
                totalSupply,
                amountOut,
                normalizedTimeRemaining,
                timeStretch,
                1 ether,
                1 ether,
                0 ether,
                0 ether
            );
        // verify that the poolBondDelta equals the amountOut/2
        assertEq(poolBondDelta, amountOut.mulDown(normalizedTimeRemaining));
        shareReserves += userDelta;
        bondReserves -= poolBondDelta;
        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            totalSupply,
            1 ether,
            positionDuration,
            timeStretch
        );
        // verify that the resulting APR is correct
        assertApproxEqAbs(result, expectedAPR.divDown(100e18), 3e12);
    }

    function test__calcFeesInGivenOut() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        (uint256 curveFee, uint256 flatFee) = hyperdriveMath
            .calculateFeesInGivenOut(
                1 ether, // amountOut
                1 ether, // timeRemaining
                0.9 ether, // spotPrice
                1 ether, // sharePrice
                0.1 ether, // curveFeePercent
                0.1 ether, // flatFeePercent
                true // isShareIn
            );
        assertEq(
            curveFee,
            .011111111111111111 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );

        (curveFee, flatFee) = hyperdriveMath.calculateFeesInGivenOut(
            1 ether, // amountOut
            1 ether, // timeRemaining
            0.9 ether, // spotPrice
            1 ether, // sharePrice
            0.1 ether, // curveFeePercent
            0.1 ether, // flatFeePercent
            false // isShareIn
        );
        assertEq(
            curveFee,
            .01 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );

        (curveFee, flatFee) = hyperdriveMath.calculateFeesInGivenOut(
            1 ether, // amountOut
            0, // timeRemaining
            0.9 ether, // spotPrice
            1 ether, // sharePrice
            0.1 ether, // curveFeePercent
            0.1 ether, // flatFeePercent
            true // isShareIn
        );
        assertEq(
            curveFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0.1 ether // ~ 0.011 ether or 10% of the price difference
        );

        (curveFee, flatFee) = hyperdriveMath.calculateFeesInGivenOut(
            1 ether, // amountOut
            0, // timeRemaining
            0.9 ether, // spotPrice
            1 ether, // sharePrice
            0.1 ether, // curveFeePercent
            0.1 ether, // flatFeePercent
            false // isShareIn
        );
        assertEq(
            curveFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0.1 ether // ~ 0.011 ether or 10% of the price difference
        );
    }

    function test__calcFeesOutGivenIn() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockHyperdriveMath hyperdriveMath = new MockHyperdriveMath();
        (uint256 curveFee, uint256 flatFee) = hyperdriveMath
            .calculateFeesOutGivenIn(
                1 ether, // amountIn
                1 ether, // timeRemaining
                0.9 ether, // spotPrice
                1 ether, // sharePrice
                0.1 ether, // curveFeePercent
                0.1 ether, // flatFeePercent
                true // isShareIn
            );
        assertEq(
            curveFee,
            .011111111111111111 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );

        (curveFee, flatFee) = hyperdriveMath.calculateFeesOutGivenIn(
            1 ether, // amountIn
            1 ether, // timeRemaining
            0.9 ether, // spotPrice
            1 ether, // sharePrice
            0.1 ether, // curveFeePercent
            0.1 ether, // flatFeePercent
            false // isShareIn
        );
        assertEq(
            curveFee,
            .01 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );

        (curveFee, flatFee) = hyperdriveMath.calculateFeesOutGivenIn(
            1 ether, // amountIn
            0, // timeRemaining
            0.9 ether, // spotPrice
            1 ether, // sharePrice
            0.1 ether, // curveFeePercent
            0.1 ether, // flatFeePercent
            true // isShareIn
        );
        assertEq(
            curveFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0.1 ether, // ~ 0.011 ether or 10% of the price difference
            "test 1"
        );

        (curveFee, flatFee) = hyperdriveMath.calculateFeesOutGivenIn(
            1 ether, // amountIn
            0, // timeRemaining
            0.9 ether, // spotPrice
            1 ether, // sharePrice
            0.1 ether, // curveFeePercent
            0.1 ether, // flatFeePercent
            false // isShareIn
        );
        assertEq(
            curveFee,
            0 ether // ~ 0.011 ether or 10% of the price difference
        );
        assertEq(
            flatFee,
            0.1 ether, // ~ 0.011 ether or 10% of the price difference
            "test 2"
        );
    }
}
