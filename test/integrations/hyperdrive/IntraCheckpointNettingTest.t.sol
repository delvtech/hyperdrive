// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { MockHyperdrive, IMockHyperdrive } from "../../mocks/MockHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

import "forge-std/console2.sol";

contract VariableInterestLongTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;


    function test_netting_open_close_long() external {

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long is opened and immediately closed
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = 0 days;
            open_close_long(initialSharePrice, variableInterest, timeElapsed);
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long is opened and closed after 182.5 days
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION/2;
            open_close_long(initialSharePrice, variableInterest, timeElapsed);
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long is opened and closed after POSITION_DURATION
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            open_close_long(initialSharePrice, variableInterest, timeElapsed);
        }
        vm.revertTo(snapshotId);
    }

    function open_close_long(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 timeElapsed
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        console2.log("poolInfo.shareReserves:", poolInfo.shareReserves.toString(18));
        console2.log("poolInfo.bondReserves:", poolInfo.bondReserves.toString(18));

        console2.log("initial exposure:", MockHyperdrive(address(hyperdrive)).getCurrentExposure().toString(18));

        // open a long
        uint256 basePaidLong = 10_000e18;
        (uint256 maturityTimeLong, uint256 bondAmount) = openLong(bob, basePaidLong);

        console2.log("after open long exposure:", MockHyperdrive(address(hyperdrive)).getCurrentExposure().toString(18));

        // fast forward time and accrue interest
        advanceTime(timeElapsed, variableInterest);

        // close the long.
        uint256 baseProceedsLong = closeLong(bob, maturityTimeLong, bondAmount);

        console2.log("after close long exposure:", MockHyperdrive(address(hyperdrive)).getCurrentExposure().toString(18));

        poolInfo = hyperdrive.getPoolInfo();
        console2.log("poolInfo.shareReserves:", poolInfo.shareReserves.toString(18));
        console2.log("poolInfo.bondReserves:", poolInfo.bondReserves.toString(18));

        console2.log("exposure:", MockHyperdrive(address(hyperdrive)).getCurrentExposure().toString(18));
        // exposure should be 0
        int256 exposure = MockHyperdrive(address(hyperdrive)).getCurrentExposure();
        assertLe(exposure, 0);
        assertApproxEqAbs(exposure,0, 1e18);
    }

    function test_netting_open_close_short() external {

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a short is opened and immediately closed
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = 0;
            open_close_short(initialSharePrice, variableInterest, timeElapsed);
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a short is opened and closed after 182.5 days
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION/2;
            open_close_short(initialSharePrice, variableInterest, timeElapsed);
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a short is opened and closed after 365 days
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            open_close_short(initialSharePrice, variableInterest, timeElapsed);
        }
        vm.revertTo(snapshotId);
    }

    function open_close_short(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 timeElapsed
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        console2.log("poolInfo.shareReserves:", poolInfo.shareReserves.toString(18));
        console2.log("poolInfo.bondReserves:", poolInfo.bondReserves.toString(18));

        console2.log("initial exposure:", MockHyperdrive(address(hyperdrive)).getCurrentExposure().toString(18));

        // open a short
        uint256 shortAmount = 10_000e18;
        (uint256 maturityTimeShort, uint256 basePaidShort) = openShort(bob, shortAmount);

        console2.log("after open short exposure:", MockHyperdrive(address(hyperdrive)).getCurrentExposure().toString(18));

        // fast forward time and accrue interest
        advanceTime(timeElapsed, variableInterest);

        // close the short
        uint256 baseProceedsShort = closeShort(bob, maturityTimeShort, shortAmount);

        console2.log("after close short exposure:", MockHyperdrive(address(hyperdrive)).getCurrentExposure().toString(18));

        poolInfo = hyperdrive.getPoolInfo();
        console2.log("poolInfo.shareReserves:", poolInfo.shareReserves.toString(18));
        console2.log("poolInfo.bondReserves:", poolInfo.bondReserves.toString(18));

        // Exposure should be 0
        int256 exposure = MockHyperdrive(address(hyperdrive)).getCurrentExposure();
        console2.log("exposure:", exposure.toString(18));
        assertLe(exposure, 0);
        assertApproxEqAbs(exposure, 0, 1e5);
    }

    function test_netting_open_close_long_short() external {

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long and short is opened and immediately closed
        uint256 snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = 0;
            open_close_long_short(initialSharePrice, variableInterest, timeElapsed);
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long and short is opened and closed after 182.5 days
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION/2;
            open_close_long_short(initialSharePrice, variableInterest, timeElapsed);
        }
        vm.revertTo(snapshotId);

        // This tests the following scenario:
        // - initial_share_price = 1
        // - positive interest causes the share price to go to up
        // - a long and short is opened and closed after 365 days
        snapshotId = vm.snapshot();
        {
            uint256 initialSharePrice = 1e18;
            int256 variableInterest = 0.05e18;
            uint256 timeElapsed = POSITION_DURATION;
            open_close_long_short(initialSharePrice, variableInterest, timeElapsed);
        }
        vm.revertTo(snapshotId);
    }

    function open_close_long_short(
        uint256 initialSharePrice,
        int256 variableInterest,
        uint256 timeElapsed
    ) internal {
        // Initialize the market
        uint256 apr = 0.05e18;
        deploy(alice, apr, initialSharePrice, 0, 0, 0);
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // fast forward time and accrue interest
        advanceTime(POSITION_DURATION, variableInterest);

        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        console2.log("poolInfo.shareReserves:", poolInfo.shareReserves.toString(18));
        console2.log("poolInfo.bondReserves:", poolInfo.bondReserves.toString(18));

        console2.log("initial exposure:", MockHyperdrive(address(hyperdrive)).getCurrentExposure().toString(18));

        // Open a long position.
        uint256 basePaidLong = 10_000e18;
        (uint256 maturityTimeLong, uint256 bondAmount) = openLong(bob, basePaidLong);

        console2.log("after open long exposure:", MockHyperdrive(address(hyperdrive)).getCurrentExposure().toString(18));

        // // Open a short position.
        uint256 shortAmount = 10_000e18;
        (uint256 maturityTimeShort, uint256 basePaidShort) = openShort(bob, shortAmount);

        console2.log("after open short exposure:", MockHyperdrive(address(hyperdrive)).getCurrentExposure().toString(18));

        // fast forward time and accrue interest
        advanceTime(timeElapsed, variableInterest);

        // close the short position.
        uint256 baseProceedsShort = closeShort(bob, maturityTimeShort, shortAmount);

        console2.log("after close short exposure:", MockHyperdrive(address(hyperdrive)).getCurrentExposure().toString(18));

        // close the long.
        uint256 baseProceedsLong = closeLong(bob, maturityTimeLong, bondAmount);

        console2.log("after close long exposure:", MockHyperdrive(address(hyperdrive)).getCurrentExposure().toString(18));

        poolInfo = hyperdrive.getPoolInfo();
        console2.log("poolInfo.shareReserves:", poolInfo.shareReserves.toString(18));
        console2.log("poolInfo.bondReserves:", poolInfo.bondReserves.toString(18));

        console2.log("exposure:", MockHyperdrive(address(hyperdrive)).getCurrentExposure().toString(18));
        // Exposure should be 0
        int256 exposure = MockHyperdrive(address(hyperdrive)).getCurrentExposure();
        assertLe(exposure, 0);
        assertApproxEqAbs(exposure,0, 1e12);
    }

}