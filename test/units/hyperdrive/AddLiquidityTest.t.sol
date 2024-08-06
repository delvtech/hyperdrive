// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract AddLiquidityTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
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
        vm.expectRevert(IHyperdrive.MinimumTransactionAmount.selector);
        hyperdrive.addLiquidity(
            0,
            0,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
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
        hyperdrive.addLiquidity{ value: 1 }(
            0,
            0,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_add_liquidity_failure_destination_zero_address() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Alice attempts to set the destination to the zero address.
        vm.stopPrank();
        vm.startPrank(alice);
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        vm.expectRevert(IHyperdrive.RestrictedZeroAddress.selector);
        hyperdrive.addLiquidity(
            contribution,
            0,
            0,
            0.04e18,
            IHyperdrive.Options({
                destination: address(0),
                asBase: true,
                extraData: new bytes(0)
            })
        );
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
        vm.expectRevert(IHyperdrive.PoolIsPaused.selector);
        hyperdrive.addLiquidity(
            0,
            0,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
        vm.stopPrank();
        pause(false);
    }

    function test_add_liquidity_failure_too_few_lp_shares_minted() external {
        uint256 apr = 0.05e18;

        // Initialize the pool
        uint256 contribution = 5e18;
        initialize(alice, apr, contribution);

        // Donate funds to pool to ensure that
        // the lpShares minted is small enough to cause a revert.
        baseToken.mint(address(hyperdrive), 100000000000e18);
        vm.stopPrank();
        vm.startPrank(bob);
        baseToken.mint(1e18);
        baseToken.approve(address(hyperdrive), 1e18);
        vm.expectRevert(IHyperdrive.MinimumTransactionAmount.selector);
        hyperdrive.addLiquidity(
            1e18,
            0,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_add_liquidity_failure_slippage_guards() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to add liquidity with a minimum APR that is too high.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.InvalidApr.selector);
        hyperdrive.addLiquidity(
            10e18,
            0,
            0.06e18,
            type(uint256).max,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Attempt to add liquidity with a maximum APR that is too low.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.InvalidApr.selector);
        hyperdrive.addLiquidity(
            10e18,
            0,
            0,
            0.04e18,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Attempt to add liquidity with a minimum LP share price that is too
        // high.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 lpSharePrice = hyperdrive.getPoolInfo().lpSharePrice;
        baseToken.mint(10e18);
        baseToken.approve(address(hyperdrive), 10e18);
        vm.expectRevert(IHyperdrive.OutputLimit.selector);
        hyperdrive.addLiquidity(
            10e18,
            2 * lpSharePrice,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_add_liquidity_failure_zero_present_value() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // A max long is opened.
        openLong(bob, hyperdrive.calculateMaxLong());

        // Alice removes her liquidity.
        removeLiquidity(alice, lpShares);

        // The term passes and zero interest accrues.
        advanceTime(POSITION_DURATION, 0);

        // Alice attempts to add liquidity again.
        vm.stopPrank();
        vm.startPrank(alice);
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        vm.expectRevert();
        hyperdrive.addLiquidity(
            contribution,
            0,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_add_liquidity_identical_lp_shares() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);
        uint256 lpSupplyBefore = hyperdrive.totalSupply(AssetId._LP_ASSET_ID);
        uint256 lpBalanceBefore = hyperdrive.balanceOf(
            AssetId._LP_ASSET_ID,
            bob
        );
        uint256 baseBalanceBefore = baseToken.balanceOf(address(hyperdrive));

        // Add liquidity with the same amount as the original contribution.
        uint256 lpShares = addLiquidity(bob, contribution);
        verifyAddLiquidityEvent(bob, lpShares, contribution);

        // Ensure that the contribution was transferred to Hyperdrive.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalanceBefore + contribution
        );

        // Ensure that the new LP receives a similar amount of LP shares as the
        // initializer. The difference will be that the new LP will receive the
        // same amount of shares as their contribution, whereas the old LP
        // received slightly less shares to set aside some shares for the
        // minimum share reserves and the zero address's initial LP contribution.
        assertEq(
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            lpSupplyBefore + lpShares
        );
        assertEq(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, bob),
            lpBalanceBefore + lpShares
        );
        assertEq(
            lpShares,
            lpSupplyBefore + hyperdrive.getPoolConfig().minimumShareReserves
        );

        // Ensure the pool APR is still approximately equal to the target APR.
        uint256 poolApr = HyperdriveUtils.calculateSpotAPR(hyperdrive);
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

        // Bob adds the same amount of liquidity as the initializer.
        uint256 lpSharePriceBefore = hyperdrive.lpSharePrice();
        uint256 bobLpShares = verifyAddLiquidity(bob, contribution);

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
            bobLpShares.mulDown(lpSharePriceBefore),
            1e9
        );

        // Ensure that all of the capital except for the minimum share reserves
        // and the zero address's LP present value was removed from the system.
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            (ONE + hyperdrive.lpSharePrice()).mulDown(
                hyperdrive.getPoolConfig().minimumShareReserves
            )
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

        // Bob adds the same amount of liquidity as the initializer.
        uint256 bobLpShares = verifyAddLiquidity(bob, contribution);

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

        // Ensure that all of the capital except for the minimum share reserves
        // and the zero address's LP present value was removed from the system.
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            (ONE + hyperdrive.lpSharePrice()).mulDown(
                hyperdrive.getPoolConfig().minimumShareReserves
            )
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

        // The term passes and no interest accrues.
        advanceTime(POSITION_DURATION, 0);

        // Get Alice's withdrawal proceeds if the long is closed immediately.
        uint256 aliceWithdrawalProceeds;
        {
            uint256 snapshotId = vm.snapshot();

            // Close the long and remove Alice's liquidity.
            closeLong(celine, maturityTime, longAmount);
            (aliceWithdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);

            vm.revertTo(snapshotId);
        }

        // Bob adds the same amount of liquidity as the initializer.
        uint256 bobLpShares = verifyAddLiquidity(bob, contribution);

        // Close Celine's long.
        closeLong(celine, maturityTime, longAmount);

        // Ensure that Alice's withdrawal proceeds are equivalent to what they
        // would have been had Bob not added liquidity.
        (
            uint256 withdrawalProceeds,
            uint256 withdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(
            withdrawalProceeds +
                withdrawalShares.mulDown(hyperdrive.lpSharePrice()),
            aliceWithdrawalProceeds,
            1
        );

        // Ensure that Bob receives his contribution back.
        (withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, contribution, 1);

        // Ensure that all of the capital except for the minimum share reserves
        // and the zero address's LP present value was removed from the system.
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            (ONE + hyperdrive.lpSharePrice()).mulDown(
                hyperdrive.getPoolConfig().minimumShareReserves
            )
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

        // The term passes and no interest accrues.
        advanceTime(POSITION_DURATION, 0);

        // Get Alice's withdrawal proceeds if the short is closed immediately.
        uint256 aliceWithdrawalProceeds;
        {
            uint256 snapshotId = vm.snapshot();

            // Close the short and remove Alice's liquidity.
            closeShort(celine, maturityTime, shortAmount);
            (aliceWithdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);

            vm.revertTo(snapshotId);
        }

        // Bob adds the same amount of liquidity as the initializer.
        uint256 bobLpShares = verifyAddLiquidity(bob, contribution);

        // Close Celine's short.
        closeShort(celine, maturityTime, shortAmount);

        // Ensure that Alice's withdrawal proceeds are equivalent to what they
        // would have been had Bob not added liquidity.
        (uint256 withdrawalProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertApproxEqAbs(withdrawalProceeds, aliceWithdrawalProceeds, 1);

        // Ensure that Bob received his contribution minus Celine's profits.
        (withdrawalProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(withdrawalProceeds, contribution, 1);

        // Ensure that all of the capital except for the minimum share reserves
        // and the zero address's LP present value was removed from the system.
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            (ONE + hyperdrive.lpSharePrice()).mulDown(
                hyperdrive.getPoolConfig().minimumShareReserves
            )
        );
    }

    function test_add_liquidity_destination() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Bob adds liquidity and sends the LP shares to Celine.
        uint256 lpShares = addLiquidity(
            bob,
            contribution,
            DepositOverrides({
                asBase: true,
                destination: celine,
                depositAmount: contribution,
                minSharePrice: 0, // min lp share price of 0
                minSlippage: 0, // min spot rate of 0
                maxSlippage: type(uint256).max, // max spot rate of uint256 max
                extraData: new bytes(0) // unused
            })
        );

        // Ensure that the correct event was emitted.
        verifyAddLiquidityEvent(celine, lpShares, contribution);

        // Ensure that Celine received the LP shares.
        assertEq(hyperdrive.balanceOf(AssetId._LP_ASSET_ID, bob), 0);
        assertEq(hyperdrive.balanceOf(AssetId._LP_ASSET_ID, celine), lpShares);
    }

    function verifyAddLiquidity(
        address lp,
        uint256 contribution
    ) internal returns (uint256 lpShares) {
        // Get the state before adding liquidity.
        uint256 spotRate = HyperdriveUtils.calculateSpotAPR(hyperdrive);
        uint256 lpSupply = hyperdrive.totalSupply(AssetId._LP_ASSET_ID);
        uint256 lpBalance = hyperdrive.balanceOf(AssetId._LP_ASSET_ID, lp);
        uint256 baseBalance = baseToken.balanceOf(address(hyperdrive));
        uint256 lpSharePrice = hyperdrive.lpSharePrice();

        // Add the liquidity and verify that the correct event was emitted.
        lpShares = addLiquidity(bob, contribution);
        verifyAddLiquidityEvent(lp, lpShares, contribution);

        // Ensure that the contribution was transferred to Hyperdrive.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            baseBalance + contribution
        );

        // Ensure that LP total supply and balances were updated correctly.
        assertEq(
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            lpSupply + lpShares
        );
        assertEq(
            hyperdrive.balanceOf(AssetId._LP_ASSET_ID, bob),
            lpBalance + lpShares
        );

        // Ensure the spot rate and the LP share price haven't changed.
        assertEq(HyperdriveUtils.calculateSpotAPR(hyperdrive), spotRate);
        assertEq(hyperdrive.lpSharePrice(), lpSharePrice);

        return lpShares;
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
        (
            uint256 lpShares,
            uint256 amount,
            uint256 vaultSharePrice,
            bool asBase,
            uint256 lpSharePrice
        ) = abi.decode(log.data, (uint256, uint256, uint256, bool, uint256));
        assertEq(lpShares, expectedLpShares);
        assertEq(amount, expectedBaseAmount);
        assertEq(vaultSharePrice, hyperdrive.getPoolInfo().vaultSharePrice);
        assertEq(asBase, true);
        assertEq(lpSharePrice, hyperdrive.getPoolInfo().lpSharePrice);
    }
}
