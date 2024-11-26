// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

// FIXME: Add full Natspec.
//
// FIXME: Add all of the failure tests.
//
// FIXME: Add assertions that show that:
//
// - The governance fees were paid.
// - The flat fee of the short was paid.
// - Variable interest was pre-paid.
// - The correct amount of bonds were minted.
//
// To make this test better, we can work backward from the bond amount to the
// full calculation.
//
// This should all contribute to ensuring solvency.
//
// FIXME: Think about what other tests we need once we have this function.
contract MintTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    // FIXME: Add a comment.
    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();

        // Deploy and initialize a pool with fees.
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.fees.curve = 0.01e18;
        config.fees.flat = 0.0005e18;
        config.fees.governanceLP = 0.15e18;
        deploy(alice, config);
        initialize(alice, 0.05e18, 100_000e18);
    }

    // FIXME:
    function test_mint_zero_amount() external {}

    // FIXME
    function test_mint_failure_not_payable() external {}

    // FIXME
    function test_mint_failure_destination_zero_address() external {}

    // FIXME
    function test_mint_failure_pause() external {}

    // FIXME
    function test_mint_failure_minVaultSharePrice() external {}

    // FIXME
    function test_mint_success() external {}

    // FIXME
    function _verifyMint() internal view {
        // FIXME
    }

    // FIXME
    function verifyOpenLongEvent() internal {
        // FIXME
    }
}
