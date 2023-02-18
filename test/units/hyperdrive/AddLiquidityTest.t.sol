// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import { HyperdriveTest } from "./HyperdriveTest.sol";

contract AddLiquidityTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_add_liquidity_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to purchase bonds with zero base. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.addLiquidity(0, 0, bob);
    }

    function test_add_liquidity_identical_lp_shares() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);
        uint256 lpShares = hyperdrive.totalSupply(AssetId._LP_ASSET_ID);
        uint256 baseBalance = baseToken.balanceOf(address(hyperdrive));

        // Add liquidity with the same amount as the original contribution.
        addLiquidity(bob, contribution);

        // Ensure that the contribution was transferred to Hyperdrive.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalance.add(contribution)
        );

        // Ensure that the new LP receives the same amount of LP shares as
        // the initializer.
        assertEq(hyperdrive.balanceOf(AssetId._LP_ASSET_ID, bob), lpShares);
        assertEq(hyperdrive.totalSupply(AssetId._LP_ASSET_ID), lpShares * 2);

        // Ensure the pool APR is still approximately equal to the target APR.
        uint256 poolApr = HyperdriveMath.calculateAPRFromReserves(
            hyperdrive.shareReserves(),
            hyperdrive.bondReserves(),
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            hyperdrive.initialSharePrice(),
            hyperdrive.positionDuration(),
            hyperdrive.timeStretch()
        );
        assertApproxEqAbs(poolApr, apr, 1);
    }
}
