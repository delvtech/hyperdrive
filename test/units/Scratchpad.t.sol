// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { MockHyperdriveMath } from "contracts/test/MockHyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../utils/HyperdriveTest.sol";
import { Lib } from "../utils/Lib.sol";

contract ScratchPad is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using HyperdriveUtils for IHyperdrive;

    uint256 fixedRate = 0.05e18;

    function setUp() public override {
        super.setUp();
        deploy(governance, fixedRate, 0.1e18, 0.1e18, 0.5e18, governance);

        uint256 initialLiquidity = 500_000_000e18;
        initialize(alice, fixedRate, initialLiquidity);
    }

    function test_open_long_tiny_negative_interest_full_update_liquidity_revert()
        external
    {
        advanceTimeToNextCheckpoint(-0.000032446749640254e18);
        (uint256 maturityTime, uint256 bondAmount) = openLong(celine, 1000e18);
    }
 }
