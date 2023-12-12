// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { MockHyperdrive } from "contracts/test/MockHyperdrive.sol";
import { HyperdriveTest, HyperdriveUtils } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";
import { console2 as console } from "forge-std/console2.sol";

contract ClosingLongsAtMaturityTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    // position opened at beginning of checkpoint
    function test_position_at_checkpoint_start() external {
        // Initialize the pool with a large amount of capital.
        int256 fixedRate = int256(0.05e18);
        uint256 contribution = 500_000_000e18;
        initialize(alice, uint256(fixedRate), contribution);
        uint256 flatFee = hyperdrive.getPoolConfig().fees.flat;

        // go to the beginning of a checkpoint and create one
        uint256 timeToNextCheckpoint = block.timestamp %
            hyperdrive.getPoolConfig().checkpointDuration;
        advanceTime(timeToNextCheckpoint, fixedRate);
        hyperdrive.checkpoint(block.timestamp);

        // Open a long position a 0% of checkpoint duration
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, uint256 bonds) = openLong(bob, baseAmount);

        // Advance to maturity.
        advanceTimeTo(maturityTime, fixedRate);
        hyperdrive.checkpoint(maturityTime);

        // Advance time again
        advanceTime(POSITION_DURATION / 2, fixedRate);

        uint256 actualBaseReceived = hyperdrive.closeLong(
            maturityTime,
            bonds,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        uint256 expectedBaseRecieved = bonds - bonds.mulDown(uint256(flatFee));

        console.log("actualBaseReceived  ", actualBaseReceived);
        console.log("expectedBaseRecieved", expectedBaseRecieved);
        int difference = int(actualBaseReceived) - int(expectedBaseRecieved);
        console.log("difference", difference);
        assertApproxEqAbs(actualBaseReceived, expectedBaseRecieved, 2);
    }

    function test_position_at_checkpoint_25_percent() external {
        // Initialize the pool with a large amount of capital.
        int256 fixedRate = int256(0.05e18);
        uint256 contribution = 500_000_000e18;
        initialize(alice, uint256(fixedRate), contribution);
        uint256 flatFee = hyperdrive.getPoolConfig().fees.flat;

        // go to the beginning of a checkpoint and create one
        uint256 timeToNextCheckpoint = block.timestamp %
            hyperdrive.getPoolConfig().checkpointDuration;
        advanceTime(timeToNextCheckpoint, fixedRate);
        hyperdrive.checkpoint(block.timestamp);

        // Open a long position a 25% of checkpoint duration
        uint256 baseAmount = 10e18;
        advanceTime(CHECKPOINT_DURATION / 4, fixedRate);
        (uint256 maturityTime, uint256 bonds) = openLong(bob, baseAmount);

        // Advance to maturity.
        advanceTimeTo(maturityTime, fixedRate);
        hyperdrive.checkpoint(maturityTime);

        // Advance time again
        advanceTime(POSITION_DURATION / 2, fixedRate);

        uint256 actualBaseReceived = hyperdrive.closeLong(
            maturityTime,
            bonds,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        uint256 expectedBaseRecieved = bonds - bonds.mulDown(uint256(flatFee));

        console.log("actualBaseReceived  ", actualBaseReceived);
        console.log("expectedBaseRecieved", expectedBaseRecieved);

        int difference = int(actualBaseReceived) - int(expectedBaseRecieved);
        console.log("difference", difference);
        assertApproxEqAbs(actualBaseReceived, expectedBaseRecieved, 2);
    }

    // Initialize the pool with a large amount of capital.
    function test_position_at_checkpoint_50_percent() external {
        int256 fixedRate = int256(0.05e18);
        uint256 contribution = 500_000_000e18;
        initialize(alice, uint256(fixedRate), contribution);
        uint256 flatFee = hyperdrive.getPoolConfig().fees.flat;

        // go to the beginning of a checkpoint and create one
        uint256 timeToNextCheckpoint = block.timestamp %
            hyperdrive.getPoolConfig().checkpointDuration;
        advanceTime(timeToNextCheckpoint, fixedRate);
        hyperdrive.checkpoint(block.timestamp);

        // Open a long position at 50% of checkpoint duration
        uint256 baseAmount = 10e18;
        advanceTime((2 * CHECKPOINT_DURATION) / 4, fixedRate);
        (uint256 maturityTime, uint256 bonds) = openLong(bob, baseAmount);

        // Advance to maturity.
        advanceTimeTo(maturityTime, fixedRate);
        hyperdrive.checkpoint(block.timestamp);

        // Advance time again.
        advanceTime(POSITION_DURATION / 2, fixedRate);

        uint256 actualBaseReceived = hyperdrive.closeLong(
            maturityTime,
            bonds,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        uint256 expectedBaseRecieved = bonds - bonds.mulDown(uint256(flatFee));

        console.log("actualBaseReceived  ", actualBaseReceived);
        console.log("expectedBaseRecieved", expectedBaseRecieved);
        int difference = int(actualBaseReceived) - int(expectedBaseRecieved);
        console.log("difference", difference);
        assertApproxEqAbs(actualBaseReceived, expectedBaseRecieved, 2);
    }

    function test_position_at_checkpoint_75_percent() external {
        // Initialize the pool with a large amount of capital.
        int256 fixedRate = int256(0.05e18);
        uint256 contribution = 500_000_000e18;
        initialize(alice, uint256(fixedRate), contribution);
        uint256 flatFee = hyperdrive.getPoolConfig().fees.flat;

        // go to the beginning of a checkpoint and create one
        uint256 timeToNextCheckpoint = block.timestamp %
            hyperdrive.getPoolConfig().checkpointDuration;
        advanceTime(timeToNextCheckpoint, fixedRate);
        hyperdrive.checkpoint(block.timestamp);

        // Open a long position at 75% of checkpoint duration
        uint256 baseAmount = 10e18;
        advanceTime((3 * CHECKPOINT_DURATION) / 4, fixedRate);
        (uint256 maturityTime, uint256 bonds) = openLong(bob, baseAmount);

        // Advance to maturity.
        advanceTimeTo(maturityTime, fixedRate);
        hyperdrive.checkpoint(maturityTime);

        // Advance time again
        advanceTime(POSITION_DURATION / 2, fixedRate);

        uint256 actualBaseReceived = hyperdrive.closeLong(
            maturityTime,
            bonds,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        uint256 expectedBaseRecieved = bonds - bonds.mulDown(uint256(flatFee));

        console.log("actualBaseReceived  ", actualBaseReceived);
        console.log("expectedBaseRecieved", expectedBaseRecieved);

        int difference = int(actualBaseReceived) - int(expectedBaseRecieved);
        console.log("difference", difference);
        assertApproxEqAbs(actualBaseReceived, expectedBaseRecieved, 2);
    }

    // function test_long_position_values_throughout_checkpoint() external {
    //     // Initialize the pool with a large amount of capital.
    //     int256 fixedRate = int256(0.05e18);
    //     uint256 contribution = 500_000_000e18;
    //     initialize(alice, uint256(fixedRate), contribution);
    //     uint256 flatFee = hyperdrive.getPoolConfig().fees.flat;

    //     // go to the beginning of a checkpoint
    //     uint256 timeToNextCheckpoint = block.timestamp %
    //         hyperdrive.getPoolConfig().checkpointDuration;
    //     advanceTime(timeToNextCheckpoint, fixedRate);

    //     // Open a long position a 0% of checkpoint duration
    //     uint256 baseAmount = 10e18;
    //     (uint256 maturityTime1, uint256 bobBonds) = openLong(bob, baseAmount);

    //     // Open a long position at 25% of checkpoint duration
    //     advanceTime(CHECKPOINT_DURATION / 4, fixedRate);
    //     (uint256 maturityTime2, uint256 celineBonds) = openLong(
    //         celine,
    //         baseAmount
    //     );

    //     // Open a long position at 50% of checkpoint duration
    //     advanceTime(CHECKPOINT_DURATION / 4, fixedRate);
    //     (uint256 maturityTime3, uint256 danBonds) = openLong(dan, baseAmount);

    //     // Open a long position at 75% of checkpoint duration
    //     advanceTime(CHECKPOINT_DURATION / 4, fixedRate);
    //     (uint256 maturityTime4, uint256 eveBonds) = openLong(eve, baseAmount);

    //     assertEq(maturityTime1, maturityTime2);
    //     assertEq(maturityTime2, maturityTime3);
    //     assertEq(maturityTime3, maturityTime4);

    //     // Advance to maturity.
    //     advanceTimeTo(maturityTime1, fixedRate);
    //     hyperdrive.checkpoint(maturityTime);

    //     // Close positions.
    //     address[4] memory addresses = [bob, celine, dan, eve];
    //     uint[4] memory bonds = [bobBonds, celineBonds, danBonds, eveBonds];

    //     for (uint i; i < 4; i++) {
    //         address user = addresses[i];
    //         uint256 userBonds = bonds[i];
    //         vm.stopPrank();
    //         vm.startPrank(user);

    //         uint256 actualBaseReceived = hyperdrive.closeLong(
    //             maturityTime1,
    //             userBonds,
    //             0,
    //             IHyperdrive.Options({
    //                 destination: user,
    //                 asBase: true,
    //                 extraData: new bytes(0)
    //             })
    //         );

    //         uint256 expectedBaseRecieved = userBonds -
    //             userBonds.mulDown(uint256(flatFee));

    //         int difference = int(actualBaseReceived) - int(expectedBaseRecieved);
    //         assertApproxEqAbs(
    //             actualBaseReceived,
    //             expectedBaseRecieved,
    //             1
    //         );
    //     }
    // }
}
