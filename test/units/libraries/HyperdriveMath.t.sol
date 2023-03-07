// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { ERC20PresetFixedSupply } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import { Test } from "forge-std/Test.sol";
import { ForwarderFactory } from "contracts/src/ForwarderFactory.sol";
import { MockHyperdriveMath } from "contracts/test/MockHyperdriveMath.sol";
import "contracts/src/libraries/FixedPointMath.sol";

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
            totalSupply,
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
        uint256 initialSharePrice = 1 ether;
        uint256 positionDuration = 365 days;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
        uint256 expectedAPR = 0.882004326279808182 ether;
        (uint256 curveIn, uint256 curveOut, uint256 flat) = hyperdriveMath
            .calculateOpenLong(
                shareReserves,
                bondReserves,
                totalSupply, // totalSupply
                50_000_000 ether, // amountIn
                FixedPointMath.ONE_18,
                timeStretch,
                1 ether, // sharePrice
                initialSharePrice
            );
        // verify that the flat part is zero
        assertEq(flat, 0);
        bondReserves -= curveOut;
        shareReserves += curveIn;
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
        uint256 normalizedTimeRemaining = 0;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
        uint256 amountIn = 503_926_401.456553339958190918 ether -
            453_456_134.637519001960754395 ether;
        (uint256 curveIn, uint256 curveOut, uint256 flat) = hyperdriveMath
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
        // verify that the curve part is zero
        assertEq(curveIn, 0);
        assertEq(curveOut, 0);
        // verify that the flat part is the amountIn * sharePrice (sharePrice = 1)
        assertEq(flat, amountIn);
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
        uint256 expectedAPR = 0.9399548487105884 ether;
        (uint256 curveIn, uint256 curveOut, ) = hyperdriveMath
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
        assertEq(curveIn, amountIn.mulDown(normalizedTimeRemaining));
        shareReserves -= curveOut;
        bondReserves += curveIn;
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
        uint256 positionDuration = 365 days;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
        uint256 expectedAPR = 1.1246406058180446 ether;
        {
            uint256 amountIn = 50_000_000 ether;
            (uint256 curveIn, uint256 curveOut, uint256 flat) = hyperdriveMath
                .calculateOpenShort(
                    shareReserves,
                    bondReserves,
                    totalSupply,
                    amountIn,
                    FixedPointMath.ONE_18,
                    timeStretch,
                    1 ether,
                    1 ether
                );
            // verify that the flat part is zero
            assertEq(flat, 0);
            bondReserves += curveIn;
            shareReserves -= curveOut;
        }
        uint256 result = hyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            totalSupply,
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
        uint256 bondReserves = 554_396_668.275587677955627441 ether;
        uint256 totalSupply = shareReserves.add(bondReserves);
        uint256 normalizedTimeRemaining = 0;
        uint256 timeStretch = FixedPointMath.ONE_18.divDown(
            110.93438508425959e18
        );
        uint256 amountOut = 50_470_266.819034337997436523 ether;
        (uint256 curveIn, uint256 curveOut, uint256 flat) = hyperdriveMath
            .calculateCloseShort(
                shareReserves,
                bondReserves,
                totalSupply,
                amountOut,
                normalizedTimeRemaining,
                timeStretch,
                1 ether,
                1 ether
            );
        // verify that the curve part is zero
        assertEq(curveOut, 0);
        assertEq(curveIn, 0);
        // verify that the flat part is the amountOut / sharePrice (sharePrice = 1)
        assertEq(flat, amountOut);
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
        uint256 expectedAPR = 1.0468643225208602 ether;
        (uint256 curveIn, uint256 curveOut, ) = hyperdriveMath
            .calculateCloseShort(
                shareReserves,
                bondReserves,
                totalSupply,
                amountOut,
                normalizedTimeRemaining,
                timeStretch,
                1 ether,
                1 ether
            );
        // verify that the poolBondDelta equals the amountOut/2
        assertEq(curveOut, amountOut.mulDown(normalizedTimeRemaining));
        shareReserves += curveOut;
        bondReserves -= curveIn;
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
}
