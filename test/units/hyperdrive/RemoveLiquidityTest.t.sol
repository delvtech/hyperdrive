// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

contract RemoveLiquidityTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_remove_liquidity_fail_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Alice attempts to remove 0 lp shares.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.removeLiquidity(0, 0, alice, false);
    }

    function test_remove_liquidity_fail_insufficient_shares() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Alice attempts to remove 0 lp shares.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.removeLiquidity(lpShares + 1, 0, alice, false);
    }

    function test_remove_liquidity_no_trades() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Time passes and interest accrues.
        uint256 timeDelta = 0.5e18;
        vm.warp(block.timestamp + POSITION_DURATION.mulDown(timeDelta));
        hyperdrive.setSharePrice(
            getPoolInfo().sharePrice.mulDown(
                FixedPointMath.ONE_18 + apr.mulDown(timeDelta)
            )
        );

        // Alice removes all of her liquidity.
        uint256 baseProceeds = removeLiquidity(alice, lpShares);

        // Ensure that the LP shares were properly accounted for.
        assertEq(hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice), 0);
        assertEq(hyperdrive.totalSupply(AssetId._LP_ASSET_ID), 0);

        // Ensure that Alice received the correct amount of base.
        assertEq(
            baseProceeds,
            calculateFutureValue(contribution, apr, timeDelta)
        );
        assertEq(baseToken.balanceOf(address(hyperdrive)), 0);

        // Ensure that the reserves were updated correctly.
        PoolInfo memory poolInfo = getPoolInfo();
        assertEq(poolInfo.shareReserves, 0);
        assertEq(poolInfo.bondReserves, 0);
        assertEq(baseToken.balanceOf(alice), baseProceeds);

        // Ensure that Alice receives the right amount of withdrawal shares.
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.LongWithdrawalShare,
                    0
                ),
                alice
            ),
            0
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.ShortWithdrawalShare,
                    0
                ),
                alice
            ),
            0
        );
    }

    function test_remove_liquidity_long_trade() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Time passes and interest accrues.
        uint256 timeDelta = 0.5e18;
        vm.warp(block.timestamp + POSITION_DURATION.mulDown(timeDelta));
        hyperdrive.setSharePrice(
            getPoolInfo().sharePrice.mulDown(
                FixedPointMath.ONE_18 + apr.mulDown(timeDelta)
            )
        );

        // Bob opens a long.
        uint256 baseAmount = 50_000_000e18;
        (, uint256 bondAmount) = openLong(bob, baseAmount);
        uint256 poolApr = calculateAPRFromReserves(hyperdrive);

        // Alice removes all of her liquidity.
        uint256 baseProceeds = removeLiquidity(alice, lpShares);

        // Ensure that the LP shares were properly accounted for.
        assertEq(hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice), 0);
        assertEq(hyperdrive.totalSupply(AssetId._LP_ASSET_ID), 0);

        // Ensure that Alice received the correct amount of base.
        uint256 baseExpected = calculateFutureValue(
            contribution,
            apr,
            timeDelta
        ) +
            baseAmount -
            bondAmount;
        assertEq(baseProceeds, baseExpected);
        assertEq(baseToken.balanceOf(address(hyperdrive)), bondAmount);
        assertEq(baseToken.balanceOf(alice), baseProceeds);

        // Ensure that the reserves were updated correctly.
        PoolInfo memory poolInfo = getPoolInfo();
        assertEq(
            poolInfo.shareReserves,
            bondAmount.divDown(getPoolInfo().sharePrice)
        );
        assertApproxEqAbs(calculateAPRFromReserves(hyperdrive), poolApr, 1 wei);

        // Ensure that Alice receives the right amount of withdrawal shares.
        uint256 longWithdrawalSharesExpected = getPoolInfo().longsOutstanding;
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.LongWithdrawalShare,
                    0
                ),
                alice
            ),
            longWithdrawalSharesExpected
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.ShortWithdrawalShare,
                    0
                ),
                alice
            ),
            0
        );
    }

    function test_remove_liquidity_short_trade() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Time passes and interest accrues.
        uint256 timeDelta = 0.5e18;
        vm.warp(block.timestamp + POSITION_DURATION.mulDown(timeDelta));
        hyperdrive.setSharePrice(
            getPoolInfo().sharePrice.mulDown(
                FixedPointMath.ONE_18 + apr.mulDown(timeDelta)
            )
        );

        // Bob opens a long.
        uint256 bondAmount = 50_000_000e18;
        (, uint256 basePaid) = openShort(bob, bondAmount);

        // Alice removes all of her liquidity.
        uint256 baseProceeds = removeLiquidity(alice, lpShares);

        // Ensure that the LP shares were properly accounted for.
        assertEq(hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice), 0);
        assertEq(hyperdrive.totalSupply(AssetId._LP_ASSET_ID), 0);

        // Ensure that Alice received the correct amount of base.
        uint256 baseExpected = calculateFutureValue(
            contribution,
            apr,
            timeDelta
        ) +
            basePaid -
            bondAmount;
        assertApproxEqAbs(baseProceeds, baseExpected, 1 wei);
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            bondAmount,
            1 wei
        );
        assertEq(baseToken.balanceOf(alice), baseProceeds);

        // Ensure that the reserves were updated correctly.
        PoolInfo memory poolInfo = getPoolInfo();
        assertEq(poolInfo.shareReserves, 0);
        assertEq(poolInfo.bondReserves, 0);

        // Ensure that Alice receives the right amount of withdrawal shares.
        uint256 shortWithdrawalSharesExpected = getPoolInfo().shortsOutstanding;
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.LongWithdrawalShare,
                    0
                ),
                alice
            ),
            0
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.ShortWithdrawalShare,
                    0
                ),
                alice
            ),
            shortWithdrawalSharesExpected
        );
    }
}
