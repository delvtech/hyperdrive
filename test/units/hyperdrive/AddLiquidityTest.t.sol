// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";

contract AddLiquidityTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_add_liquidity_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to add zero base as liquidity. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.addLiquidity(0, 0, type(uint256).max, bob, true);
    }

    function test_add_liquidity_failure_invalid_apr() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to add liquidity with a minimum APR that is too high.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.InvalidApr.selector);
        hyperdrive.addLiquidity(10e18, 0.06e18, type(uint256).max, bob, true);

        // Attempt to add liquidity with a maximum APR that is too low.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.InvalidApr.selector);
        hyperdrive.addLiquidity(10e18, 0, 0.04e18, bob, true);
    }

    function test_add_liquidity_identical_lp_shares() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);
        uint256 lpSupplyBefore = hyperdrive.totalSupply(AssetId._LP_ASSET_ID);
        uint256 baseBalance = baseToken.balanceOf(address(hyperdrive));

        // Add liquidity with the same amount as the original contribution.
        uint256 lpShares = addLiquidity(bob, contribution);

        // Ensure that the contribution was transferred to Hyperdrive.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalance.add(contribution)
        );

        // Ensure that the new LP receives the same amount of LP shares as
        // the initializer.
        assertEq(lpShares, lpSupplyBefore);
        assertEq(
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            lpSupplyBefore * 2
        );

        // Ensure the pool APR is still approximately equal to the target APR.
        uint256 poolApr = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);
        assertApproxEqAbs(poolApr, apr, 1);
    }

    function test_add_liquidity_with_long_immediately() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);
        uint256 lpSupplyBefore = hyperdrive.totalSupply(AssetId._LP_ASSET_ID);

        // Celine opens a long.
        openLong(celine, 50_000_000e18);

        // Add liquidity with the same amount as the original contribution.
        uint256 aprBefore = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
        uint256 baseBalance = baseToken.balanceOf(address(hyperdrive));
        uint256 lpShares = addLiquidity(bob, contribution);

        // Ensure that the contribution was transferred to Hyperdrive.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalance.add(contribution)
        );

        // Ensure that the new LP receives the same amount of LP shares as
        // the initializer.
        assertEq(lpShares, lpSupplyBefore);
        assertEq(
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            lpSupplyBefore * 2
        );

        // Ensure the pool APR is still approximately equal to the target APR.
        uint256 aprAfter = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);
        assertApproxEqAbs(aprAfter, aprBefore, 1);
    }

    function test_add_liquidity_with_short_immediately() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);
        uint256 lpSupplyBefore = hyperdrive.totalSupply(AssetId._LP_ASSET_ID);

        // Celine opens a short.
        openShort(celine, 50_000_000e18);

        // Add liquidity with the same amount as the original contribution.
        uint256 aprBefore = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
        uint256 baseBalance = baseToken.balanceOf(address(hyperdrive));
        uint256 lpShares = addLiquidity(bob, contribution);

        // Ensure that the contribution was transferred to Hyperdrive.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalance.add(contribution)
        );

        // Ensure that the new LP receives the same amount of LP shares as
        // the initializer.
        assertEq(lpShares, lpSupplyBefore);
        assertEq(
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            lpSupplyBefore * 2
        );

        // Ensure the pool APR is still approximately equal to the target APR.
        uint256 aprAfter = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);
        assertApproxEqAbs(aprAfter, aprBefore, 1);
    }

    function test_add_liquidity_with_long_at_maturity() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);
        hyperdrive.totalSupply(AssetId._LP_ASSET_ID);

        // Celine opens a long.
        openLong(celine, 50_000_000e18);

        // The term passes.
        vm.warp(block.timestamp + POSITION_DURATION);

        // Add liquidity with the same amount as the original contribution.
        uint256 aprBefore = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
        uint256 baseBalance = baseToken.balanceOf(address(hyperdrive));
        uint256 lpShares = addLiquidity(bob, contribution);

        // TODO: This suggests an issue with the flat+curve usage in the
        //       checkpointing mechanism. These APR figures should be the same.
        //
        // Ensure the pool APR hasn't decreased after adding liquidity.
        uint256 aprAfter = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);
        assertGe(aprAfter, aprBefore);

        // Ensure that the contribution was transferred to Hyperdrive.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalance.add(contribution)
        );

        // Ensure that if the new LP withdraws, they get their money back.
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, contribution, 1e9);
    }

    function test_add_liquidity_with_short_at_maturity() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Celine opens a short.
        openShort(celine, 50_000_000e18);

        // The term passes.
        vm.warp(block.timestamp + POSITION_DURATION);

        // Add liquidity with the same amount as the original contribution.
        uint256 aprBefore = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
        uint256 baseBalance = baseToken.balanceOf(address(hyperdrive));
        uint256 lpShares = addLiquidity(bob, contribution);

        // TODO: This suggests an issue with the flat+curve usage in the
        //       checkpointing mechanism. These APR figures should be the same.
        //
        // Ensure the pool APR hasn't increased after adding liquidity.
        uint256 aprAfter = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);
        assertLe(aprAfter, aprBefore);

        // Ensure that the contribution was transferred to Hyperdrive.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalance.add(contribution)
        );

        // Ensure that if the new LP withdraws, they get their money back.
        (uint256 withdrawalProceeds, ) = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(withdrawalProceeds, contribution, 1e9);
    }
}
