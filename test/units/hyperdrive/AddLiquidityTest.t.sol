// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract AddLiquidityTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_add_liquidity_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to add zero base as liquidity. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.ZeroAmount.selector);
        hyperdrive.addLiquidity(0, 0, type(uint256).max, bob, true);
    }

    function test_add_liquidity_failure_not_payable() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to add zero base as liquidity. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.addLiquidity{ value: 1 }(0, 0, type(uint256).max, bob, true);
    }

    function test_add_liquidity_failure_pause() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to add zero base as liquidity. This should fail.
        vm.stopPrank();
        pause(true);
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.Paused.selector);
        hyperdrive.addLiquidity(0, 0, type(uint256).max, bob, true);
        vm.stopPrank();
        pause(false);
    }

    function test_add_liquidity_failure_invalid_apr() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to add liquidity with a minimum APR that is too high.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.InvalidApr.selector);
        hyperdrive.addLiquidity(10e18, 0.06e18, type(uint256).max, bob, true);

        // Attempt to add liquidity with a maximum APR that is too low.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.InvalidApr.selector);
        hyperdrive.addLiquidity(10e18, 0, 0.04e18, bob, true);
    }

    function test_add_liquidity_failure_zero_lp_total_supply() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Bob opens a long.
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, 10e18);

        // Alice removes her liquidity.
        removeLiquidity(alice, lpShares);

        // Bob closes his long.
        closeLong(bob, maturityTime, longAmount);

        // Attempt to add liquidity when the LP total supply is zero. This
        vm.stopPrank();
        vm.startPrank(bob);
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        vm.expectRevert();
        hyperdrive.addLiquidity(contribution, 0, 0.04e18, bob, true);
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
        verifyAddLiquidityEvent(bob, lpShares, contribution);

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

    function test_add_liquidity_with_long_at_open() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, apr, contribution);

        // Celine opens a long.
        uint256 basePaid = 50_000_000e18;
        (uint256 maturityTime, uint256 longAmount) = openLong(celine, basePaid);

        // Get Alice's withdrawal proceeds if the long is closed immediately.
        uint256 aliceWithdrawalProceeds;
        {
            uint256 snapshotId = vm.snapshot();

            // Close the long and remove Alice's liquidity.
            closeLong(celine, maturityTime, longAmount);
            (aliceWithdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);

            vm.revertTo(snapshotId);
        }

        // Add liquidity with the same amount as the original contribution.
        uint256 aprBefore = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
        uint256 baseBalanceBefore = baseToken.balanceOf(address(hyperdrive));
        uint256 presentValueRatioBefore = presentValueRatio();
        uint256 bobLpShares = addLiquidity(bob, contribution);
        verifyAddLiquidityEvent(bob, bobLpShares, contribution);

        // Ensure that adding liquidity didn't change Alice's LP share balance.
        assertEq(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            aliceLpShares
        );

        // Ensure that the present value ratio was preserved.
        assertEq(presentValueRatio(), presentValueRatioBefore);

        // Ensure that the contribution was transferred to Hyperdrive.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalanceBefore + contribution
        );

        // Ensure the pool APR is still approximately equal to the target APR.
        {
            uint256 aprAfter = HyperdriveUtils.calculateAPRFromReserves(
                hyperdrive
            );
            assertApproxEqAbs(aprAfter, aprBefore, 1);
        }

        // Close Celine's long.
        closeLong(celine, maturityTime, longAmount);

        // Ensure that Alice's withdrawal proceeds are equivalent to what they
        // would have been had Bob not added liquidity.
        (uint256 withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertEq(withdrawalProceeds, aliceWithdrawalProceeds);

        // Ensure that Bob received his contribution minus Celine's profits.
        (withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(
            withdrawalProceeds,
            bobLpShares.mulDown(presentValueRatioBefore),
            1e9
        );

        // Ensure that all of the capital (except for the minimum share reserves)
        // has been removed from the system.
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves
        );
    }

    function test_add_liquidity_with_short_at_open() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, apr, contribution);

        // Celine opens a short.
        uint256 shortAmount = 50_000_000e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(
            celine,
            shortAmount
        );

        // Get Alice's withdrawal proceeds if the short is closed immediately.
        uint256 aliceWithdrawalProceeds;
        {
            uint256 snapshotId = vm.snapshot();

            // Close the short and remove Alice's liquidity.
            closeShort(celine, maturityTime, shortAmount);
            (aliceWithdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);

            vm.revertTo(snapshotId);
        }

        // Add liquidity with the same amount as the original contribution.
        uint256 aprBefore = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
        uint256 baseBalanceBefore = baseToken.balanceOf(address(hyperdrive));
        uint256 presentValueRatioBefore = presentValueRatio();
        uint256 bobLpShares = addLiquidity(bob, contribution);
        verifyAddLiquidityEvent(bob, bobLpShares, contribution);

        // Ensure that adding liquidity didn't change Alice's LP share balance.
        assertEq(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            aliceLpShares
        );

        // Ensure that the present value ratio was preserved.
        assertEq(presentValueRatio(), presentValueRatioBefore);

        // Ensure that the contribution was transferred to Hyperdrive.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalanceBefore.add(contribution)
        );

        // Ensure the pool APR is still approximately equal to the target APR.
        uint256 aprAfter = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);
        assertApproxEqAbs(aprAfter, aprBefore, 1);

        // Close Celine's short.
        uint256 shortProceeds = closeShort(celine, maturityTime, shortAmount);

        // Ensure that Alice's withdrawal proceeds are equivalent to what they
        // would have been had Bob not added liquidity.
        (uint256 withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertEq(withdrawalProceeds, aliceWithdrawalProceeds);

        // Ensure that Bob received his contribution minus Celine's profits.
        (withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(
            withdrawalProceeds,
            contribution - (shortProceeds - basePaid),
            1e10
        );

        // Ensure that all of the capital has been removed from the system.
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves
        );
    }

    function test_add_liquidity_with_long_at_maturity() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, apr, contribution);

        // Celine opens a long.
        uint256 basePaid = 50_000_000e18;
        (uint256 maturityTime, uint256 longAmount) = openLong(celine, basePaid);

        // The term passes.
        vm.warp(block.timestamp + POSITION_DURATION);

        // Get Alice's withdrawal proceeds if the long is closed immediately.
        uint256 aliceWithdrawalProceeds;
        {
            uint256 snapshotId = vm.snapshot();

            // Close the long and remove Alice's liquidity.
            closeLong(celine, maturityTime, longAmount);
            (aliceWithdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);

            vm.revertTo(snapshotId);
        }

        // Add liquidity with the same amount as the original contribution.
        uint256 aprBefore = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
        uint256 baseBalanceBefore = baseToken.balanceOf(address(hyperdrive));
        uint256 presentValueRatioBefore = presentValueRatio();
        uint256 bobLpShares = addLiquidity(bob, contribution);
        verifyAddLiquidityEvent(bob, bobLpShares, contribution);

        // Ensure that adding liquidity didn't change Alice's LP share balance.
        assertEq(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            aliceLpShares
        );

        // Ensure that the present value ratio was preserved.
        assertEq(presentValueRatio(), presentValueRatioBefore);

        // Ensure that the contribution was transferred to Hyperdrive.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalanceBefore.add(contribution)
        );

        // Ensure the pool APR hasn't decreased after adding liquidity.
        uint256 aprAfter = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);
        assertEq(aprAfter, aprBefore);

        // Close Celine's long.
        closeLong(celine, maturityTime, longAmount);

        // Ensure that Alice's withdrawal proceeds are equivalent to what they
        // would have been had Bob not added liquidity.
        (uint256 withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(withdrawalProceeds, aliceWithdrawalProceeds, 1);

        // Ensure that Bob receives his contribution back.
        (withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, contribution, 1);

        // Ensure that all of the capital has been removed from the system.
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves
        );
    }

    function test_add_liquidity_with_short_at_maturity() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, apr, contribution);

        // Celine opens a short.
        uint256 shortAmount = 50_000_000e18;
        (uint256 maturityTime, ) = openShort(celine, shortAmount);

        // The term passes.
        vm.warp(block.timestamp + POSITION_DURATION);

        // Get Alice's withdrawal proceeds if the short is closed immediately.
        uint256 aliceWithdrawalProceeds;
        {
            uint256 snapshotId = vm.snapshot();

            // Close the short and remove Alice's liquidity.
            closeShort(celine, maturityTime, shortAmount);
            (aliceWithdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);

            vm.revertTo(snapshotId);
        }

        // Add liquidity with the same amount as the original contribution.
        uint256 aprBefore = HyperdriveUtils.calculateAPRFromReserves(
            hyperdrive
        );
        uint256 baseBalanceBefore = baseToken.balanceOf(address(hyperdrive));
        uint256 presentValueRatioBefore = presentValueRatio();
        uint256 bobLpShares = addLiquidity(bob, contribution);
        verifyAddLiquidityEvent(bob, bobLpShares, contribution);

        // Ensure the pool APR hasn't increased after adding liquidity.
        uint256 aprAfter = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);
        assertEq(aprAfter, aprBefore);

        // Ensure that adding liquidity didn't change Alice's LP share balance.
        assertEq(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice),
            aliceLpShares
        );

        // Ensure that the present value ratio was preserved.
        assertEq(presentValueRatio(), presentValueRatioBefore);

        // Ensure that the contribution was transferred to Hyperdrive.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalanceBefore.add(contribution)
        );

        // Close Celine's short.
        closeShort(celine, maturityTime, shortAmount);

        // Ensure that Alice's withdrawal proceeds are equivalent to what they
        // would have been had Bob not added liquidity.
        (uint256 withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertEq(withdrawalProceeds, aliceWithdrawalProceeds);

        // Ensure that Bob received his contribution minus Celine's profits.
        (withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, contribution, 1);

        // Ensure that all of the capital (except for the minimum share reserves)
        // has been removed from the system.
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdrive.getPoolConfig().minimumShareReserves
        );
    }

    function verifyAddLiquidityEvent(
        address provider,
        uint256 expectedLpShares,
        uint256 expectedBaseAmount
    ) internal {
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            AddLiquidity.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(address(uint160(uint256(log.topics[1]))), provider);
        (uint256 lpShares, uint256 baseAmount) = abi.decode(
            log.data,
            (uint256, uint256)
        );
        assertEq(lpShares, expectedLpShares);
        assertEq(baseAmount, expectedBaseAmount);
    }

    function presentValueRatio() internal view returns (uint256) {
        uint256 totalLpSupply = hyperdrive.totalSupply(AssetId._LP_ASSET_ID) +
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID) -
            hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw -
            hyperdrive.getPoolConfig().minimumShareReserves;
        return HyperdriveUtils.presentValue(hyperdrive).divDown(totalLpSupply);
    }
}
