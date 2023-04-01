// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";

contract InitializeTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_initialize_failure_reinitialization() external {
        uint256 apr = 0.5e18;
        uint256 contribution = 1000.0e18;

        // Initialize the pool with Alice.
        uint256 lpShares = initialize(alice, apr, contribution);

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
        uint256 baseBalanceBefore = baseToken.balanceOf(address(hyperdrive));
        uint256 lpShares = initialize(alice, apr, contribution);
        uint256 baseBalanceAfter = baseToken.balanceOf(address(hyperdrive));

        // Ensure that the pool's APR is approximately equal to the target APR.
        uint256 poolApr = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);
        assertApproxEqAbs(poolApr, apr, 1); // 17 decimals of precision

        // Ensure that Alice's base balance has been depleted and that Alice
        // received the correct amount of LP shares.
        assertEq(baseToken.balanceOf(alice), 0);
        assertEq(baseBalanceAfter, baseBalanceBefore + contribution);
        assertEq(
            lpShares,
            hyperdrive.getPoolInfo().bondReserves -
                HyperdriveMath.calculateInitialBondReserves(
                    contribution,
                    FixedPointMath.ONE_18,
                    FixedPointMath.ONE_18,
                    apr,
                    POSITION_DURATION,
                    hyperdrive.getPoolConfig().timeStretch
                )
        );
    }
}
