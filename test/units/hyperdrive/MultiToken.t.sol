// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { SafeCast } from "contracts/src/libraries/SafeCast.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { MockHyperdrive, IMockHyperdrive } from "contracts/test/MockHyperdrive.sol";
import { HyperdriveTest, HyperdriveUtils } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract HyperdriveMultiToken is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using SafeCast for uint256;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_transferFrom() external {
        initialize(alice, 0.05e18, 10_000e18);
        // test alice to bob transfer
        (uint256 maturityTime, uint256 bondProceeds) = openLong(alice, 100e18);

        // uint245 bobBalanceBefore = hyperdrive.balanceOf(
        //     AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
        //     bob
        // );

        vm.startPrank(alice);

        hyperdrive.transferFrom(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            alice,
            bob,
            bondProceeds
        );

        uint256 bobBalance = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bob
        );

        assertEq(bobBalance, bondProceeds);
    }
}
