// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract InitializeTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_initialize_failure() external {
        // Initialize the pool with Alice.
        uint256 fixedRate = 0.5e18;
        uint256 contribution = 1000.0e18;
        uint256 lpShares = initialize(alice, fixedRate, contribution);
        verifyInitializeEvent(alice, lpShares, contribution, fixedRate);

        // Alice removes all of her liquidity.
        removeLiquidity(alice, lpShares);

        // Attempt to initialize the pool a second time. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        vm.expectRevert(IHyperdrive.PoolAlreadyInitialized.selector);
        hyperdrive.initialize(contribution, fixedRate, bob, true);
    }

    function test_initialize_failure_not_payable() external {
        // Attempt to initialize the pool. This should fail.
        uint256 fixedRate = 0.5e18;
        uint256 contribution = 1000.0e18;
        vm.stopPrank();
        vm.startPrank(bob);
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.initialize{ value: 1 }(contribution, fixedRate, bob, true);
    }

    // FIXME: Address this test.
    //
    // TODO: This should ultimately be a fuzz test that fuzzes over the initial
    // share price, the fixed rate, the contribution, the position duration, and
    // other parameters that can have an impact on the pool's spot rate.
    function test_initialize_success(
        uint256 fixedRate,
        uint256 contribution
    ) external {
        // Initialize the pool with Alice.
        fixedRate = fixedRate.normalizeToRange(0.01e18, 1e18);
        contribution = contribution.normalizeToRange(1000e18, 500_000_000e18);
        uint256 lpShares = initialize(alice, fixedRate, contribution);
        verifyInitializeEvent(alice, lpShares, contribution, fixedRate);

        // Ensure that the pool's spot rate is approximately equal to the target
        // spot rate.
        uint256 spotRate = hyperdrive.calculateSpotRate();
        assertApproxEqAbs(spotRate, fixedRate, 1e6); // 12 decimals of precision

        // Ensure that Alice's base balance has been depleted and that Alice
        // received the correct amount of LP shares.
        assertEq(baseToken.balanceOf(alice), 0);
        assertEq(baseToken.balanceOf(address(hyperdrive)), contribution);
        assertEq(
            lpShares,
            hyperdrive.getPoolInfo().shareReserves - 2 * MINIMUM_SHARE_RESERVES
        );

        // Ensure that the total supply of LP shares and Alice's balance of LP
        // shares are correct.
        assertEq(
            lpShares,
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID) -
                MINIMUM_SHARE_RESERVES
        );
        assertEq(lpShares, hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice));
    }

    function verifyInitializeEvent(
        address provider,
        uint256 expectedLpShares,
        uint256 expectedBaseAmount,
        uint256 expectedSpotRate
    ) internal {
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            Initialize.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(address(uint160(uint256(log.topics[1]))), provider);
        (uint256 lpShares, uint256 baseAmount, uint256 spotRate) = abi.decode(
            log.data,
            (uint256, uint256, uint256)
        );
        assertEq(lpShares, expectedLpShares);
        assertEq(baseAmount, expectedBaseAmount);
        assertEq(spotRate, expectedSpotRate);
    }
}
