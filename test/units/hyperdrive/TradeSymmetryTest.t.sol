// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";
import "forge-std/console2.sol";

contract TradeSymmetryTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_long_symmetry_immediately_at_checkpoint() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        IHyperdrive.PoolConfig memory config = hyperdrive.getPoolConfig();

        // Get the poolinfo before opening the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Immediately close the long.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Get the poolinfo after closing the long.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        console2.log("poolInfoBefore.shareReserves", poolInfoBefore.shareReserves);
        console2.log("poolInfoBefore.bondReserves", poolInfoBefore.bondReserves);
        console2.log("poolInfoAfter.shareReserves", poolInfoAfter.shareReserves);
        console2.log("poolInfoAfter.bondReserves", poolInfoAfter.bondReserves);
        // if they aren't the same, then the pool should be the one that wins
        assertGe(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);
        // should be exact if out = in
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);

    }

    function test_long_symmetry_immediately_halfway_thru_checkpoint() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        IHyperdrive.PoolConfig memory config = hyperdrive.getPoolConfig();

        // Get the poolinfo before opening the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // fast forward time to halfway through checkpoint
        advanceTime(CHECKPOINT_DURATION/2, 0);
        
        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Immediately close the long.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Get the poolinfo after closing the long.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        console2.log("poolInfoBefore.shareReserves", poolInfoBefore.shareReserves);
        console2.log("poolInfoBefore.bondReserves", poolInfoBefore.bondReserves);
        console2.log("poolInfoAfter.shareReserves", poolInfoAfter.shareReserves);
        console2.log("poolInfoAfter.bondReserves", poolInfoAfter.bondReserves);
        // if they aren't the same, then the pool should be the one that wins
        assertGe(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);
        // should be exact if out = in
        assertEq(poolInfoAfter.bondReserves, poolInfoBefore.bondReserves);

    }


}
