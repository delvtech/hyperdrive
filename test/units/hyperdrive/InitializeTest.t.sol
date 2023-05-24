// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { VmSafe } from "forge-std/Vm.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract InitializeTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_initialize_failure() external {
        uint256 apr = 0.5e18;
        uint256 contribution = 1000.0e18;

        // Initialize the pool with Alice.
        uint256 lpShares = initialize(alice, apr, contribution);
        verifyInitializeEvent(alice, lpShares, contribution, apr);

        // Alice removes all of her liquidity.
        removeLiquidity(alice, lpShares);

        // Attempt to initialize the pool a second time. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        vm.expectRevert(Errors.PoolAlreadyInitialized.selector);
        hyperdrive.initialize(contribution, apr, bob, true);
    }

    // TODO: This should ultimately be a fuzz test that fuzzes over the initial
    // share price, the APR, the contribution, the position duration, and other
    // parameters that can have an impact on the pool's APR.
    function test_initialize_success() external {
        uint256 apr = 0.05e18;
        uint256 contribution = 1000e18;

        // Initialize the pool with Alice.
        uint256 lpShares = initialize(alice, apr, contribution);
        verifyInitializeEvent(alice, lpShares, contribution, apr);

        // Ensure that the pool's APR is approximately equal to the target APR.
        uint256 poolApr = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);
        assertApproxEqAbs(poolApr, apr, 1); // 17 decimals of precision

        // Ensure that Alice's base balance has been depleted and that Alice
        // received the correct amount of LP shares.
        assertEq(baseToken.balanceOf(alice), 0);
        assertEq(baseToken.balanceOf(address(hyperdrive)), contribution);
        assertEq(
            lpShares,
            hyperdrive.getPoolInfo().bondReserves
                - HyperdriveMath.calculateInitialBondReserves(
                    contribution,
                    FixedPointMath.ONE_18,
                    FixedPointMath.ONE_18,
                    apr,
                    POSITION_DURATION,
                    hyperdrive.getPoolConfig().timeStretch
                )
        );
    }

    function verifyInitializeEvent(
        address provider,
        uint256 expectedLpShares,
        uint256 expectedBaseAmount,
        uint256 expectedApr
    ) internal {
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(Initialize.selector);
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(address(uint160(uint256(log.topics[1]))), provider);
        (uint256 lpShares, uint256 baseAmount, uint256 apr) = abi.decode(log.data, (uint256, uint256, uint256));
        assertEq(lpShares, expectedLpShares);
        assertEq(baseAmount, expectedBaseAmount);
        assertEq(apr, expectedApr);
    }
}
