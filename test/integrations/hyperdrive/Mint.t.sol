// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

/// @dev An integration test suite for the mint function.
contract MintTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    /// @dev Sets up the harness and deploys and initializes a pool with fees.
    function setUp() public override {
        // Run the higher level setup function.
        super.setUp();

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

    // FIXME: We need integration tests that ensure that mint interoperates with
    // the rest of the AMM. Here are a few tests that we should be particularly
    // mindful of:
    //
    // - Mint and then close long.
    // - Mint and then close short.
    // - Mint and then add liquidity.
    // - Mint and then remove liquidity.
    //
    // Some things to think about are:
    //
    // - Mint's affect on solvency
    // - Mint's affect on pricing
    // - Whether or not anything is unaccounted for after closing the position.

    // FIXME
    function test_mint_and_close_long() external {
        //
    }
}
