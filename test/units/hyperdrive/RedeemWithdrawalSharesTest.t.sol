// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract RedeemWithdrawalSharesTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_redeem_withdrawal_shares_failure_output_limit() external {
        // Initialize the pool.
        uint256 lpShares = initialize(alice, 0.02e18, 500_000_000e18);

        // Bob opens a large short.
        uint256 shortAmount = HyperdriveUtils.calculateMaxShort(hyperdrive);
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // Alice removes her liquidity.
        (, uint256 withdrawalShares) = removeLiquidity(alice, lpShares);

        // The term passes and no interest accrues.
        advanceTime(POSITION_DURATION, 0);

        // Bob closes his short.
        closeShort(bob, maturityTime, shortAmount);

        // Alice tries to redeem her withdrawal shares with a large output limit.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(IHyperdrive.OutputLimit.selector);
        uint256 expectedOutputPerShare = shortAmount.divDown(withdrawalShares);
        hyperdrive.redeemWithdrawalShares(
            withdrawalShares,
            2 * expectedOutputPerShare,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_redeem_withdrawal_shares_no_clamping() external {
        // Initialize the pool.
        uint256 lpShares = initialize(alice, 0.02e18, 500_000_000e18);

        // Bob opens a large short.
        uint256 shortAmount = HyperdriveUtils.calculateMaxShort(hyperdrive);
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // Alice removes her liquidity.
        (, uint256 withdrawalShares) = removeLiquidity(alice, lpShares);

        // The term passes and no interest accrues.
        advanceTime(POSITION_DURATION, 0);

        // Bob closes his short.
        closeShort(bob, maturityTime, shortAmount);

        // Alice redeems her withdrawal shares. The proceeds of the trade are
        // used to pay out the withdrawal pool, so we can approximate Alice's
        // proceeds by splitting the short proceeds in proportion to LP shares.
        // Her actual proceeds will be slightly higher to compensate her for the
        // proportional increase in the present value as her shares are removed
        // from the share reserves.
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );
        (uint256 baseProceeds, uint256 sharesRedeemed) = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        uint256 expectedProceeds = shortAmount.mulDivDown(
            withdrawalShares,
            withdrawalShares + hyperdrive.getPoolConfig().minimumShareReserves
        );
        assertApproxEqAbs(baseProceeds, expectedProceeds, 1e14);
        assertGt(baseProceeds, expectedProceeds);
        assertEq(sharesRedeemed, withdrawalShares);

        // Ensure that a `RedeemWithdrawalShares` event was emitted.
        verifyRedeemWithdrawalSharesEvent(alice, sharesRedeemed, baseProceeds);

        // Ensure that all of the withdrawal shares were burned.
        assertEq(hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID), 0);
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw, 0);
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesProceeds, 0);

        // Ensure that the base proceeds were transferred.
        assertEq(
            baseToken.balanceOf(alice),
            aliceBaseBalanceBefore + baseProceeds
        );
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdriveBaseBalanceBefore - baseProceeds
        );
    }

    function test_redeem_withdrawal_shares_clamping() external {
        // Initialize the pool.
        uint256 lpShares = initialize(alice, 0.02e18, 500_000_000e18);

        // Bob opens a large short.
        uint256 shortAmount = HyperdriveUtils.calculateMaxShort(hyperdrive);
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // Alice removes her liquidity.
        (, uint256 withdrawalShares) = removeLiquidity(alice, lpShares);

        // The term passes and no interest accrues.
        advanceTime(POSITION_DURATION, 0);

        // Bob closes his short.
        closeShort(bob, maturityTime, shortAmount);

        // The proceeds of the trade are used to pay out the withdrawal pool.
        // We can approximate Alice's proceeds by splitting the short proceeds
        // in proportion to LP shares. Her actual proceeds will be slightly
        // higher to compensate her for the proportional increase in the present
        // value as her shares are removed from the share reserves.
        uint256 aliceProceeds = shortAmount.mulDivDown(
            withdrawalShares,
            withdrawalShares + hyperdrive.getPoolConfig().minimumShareReserves
        );

        // Alice redeems half of her withdrawal shares.
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );
        (uint256 baseProceeds, uint256 sharesRedeemed) = redeemWithdrawalShares(
            alice,
            withdrawalShares / 2
        );
        assertApproxEqAbs(baseProceeds, aliceProceeds / 2, 1e14);
        assertGt(baseProceeds, aliceProceeds / 2);
        assertApproxEqAbs(sharesRedeemed, withdrawalShares / 2, 1);

        // Ensure that a `RedeemWithdrawalShares` event was emitted.
        verifyRedeemWithdrawalSharesEvent(alice, sharesRedeemed, baseProceeds);

        // Ensure that the base proceeds were transferred.
        assertEq(
            baseToken.balanceOf(alice),
            aliceBaseBalanceBefore + baseProceeds
        );
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdriveBaseBalanceBefore - baseProceeds
        );

        // Alice redeems the next half of her withdrawal shares.
        aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        hyperdriveBaseBalanceBefore = baseToken.balanceOf(address(hyperdrive));
        (baseProceeds, sharesRedeemed) = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertApproxEqAbs(baseProceeds, aliceProceeds / 2, 1e14);
        assertGt(baseProceeds, aliceProceeds / 2);
        assertApproxEqAbs(sharesRedeemed, withdrawalShares / 2, 1);

        // Ensure that a `RedeemWithdrawalShares` event was emitted.
        verifyRedeemWithdrawalSharesEvent(alice, sharesRedeemed, baseProceeds);

        // Ensure that all of the withdrawal shares were burned.
        assertEq(hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID), 0);
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw, 0);
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesProceeds, 0);

        // Ensure that the base proceeds were transferred.
        assertEq(
            baseToken.balanceOf(alice),
            aliceBaseBalanceBefore + baseProceeds
        );
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdriveBaseBalanceBefore - baseProceeds
        );
    }

    function test_redeem_withdrawal_shares_long_halfway_through_term()
        external
    {
        // Initialize the pool.
        uint256 contribution = 500_000_000e18;
        uint256 fixedRate = 0.02e18;
        uint256 lpShares = initialize(alice, fixedRate, contribution);
        // Bob opens a large long.
        uint256 basePaidLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            basePaidLong
        );
        // Alice removes her liquidity.
        (uint256 lpProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );

        // The term passes and no interest accrues.
        advanceTime(POSITION_DURATION / 2, 0);

        // Bob closes his long. He will not get as much back bc there will be
        // more slippage on the curve due to the liquidity removed by Alice.
        closeLong(bob, maturityTime, longAmount);

        // Get the base balances before the trade.
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Alice redeems her withdrawal shares.
        (
            uint256 withdrawalSharesProceeds,
            uint256 sharesRedeemed
        ) = redeemWithdrawalShares(alice, withdrawalShares);

        // Ensure that lps total proceeds are greater than the amount they contributed.
        assertGt(withdrawalSharesProceeds + lpProceeds, contribution);

        // Ensure that a `RedeemWithdrawalShares` event was emitted.
        verifyRedeemWithdrawalSharesEvent(
            alice,
            sharesRedeemed,
            withdrawalSharesProceeds
        );

        // Ensure that the base proceeds were transferred.
        assertEq(
            baseToken.balanceOf(alice),
            aliceBaseBalanceBefore + withdrawalSharesProceeds
        );
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdriveBaseBalanceBefore - withdrawalSharesProceeds
        );
    }

    function test_redeem_withdrawal_shares_min_output() external {
        // Initialize the pool.
        uint256 lpShares = initialize(alice, 0.02e18, 500_000_000e18);

        // Bob opens a large short.
        uint256 shortAmount = HyperdriveUtils.calculateMaxShort(hyperdrive);
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // Alice removes her liquidity.
        (, uint256 withdrawalShares) = removeLiquidity(alice, lpShares);

        // The term passes and no interest accrues.
        advanceTime(POSITION_DURATION, 0);

        // Bob closes his short.
        closeShort(bob, maturityTime, shortAmount);

        // Alice redeems her withdrawal shares. We can approximate Alice's
        // proceeds by splitting the short proceeds in proportion to LP shares.
        // Her actual proceeds will be slightly higher to compensate her for the
        // proportional increase in the present value as her shares are removed
        // from the share reserves.
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );
        uint256 expectedSharePrice = shortAmount.divDown(
            withdrawalShares + hyperdrive.getPoolConfig().minimumShareReserves
        );
        (uint256 baseProceeds, uint256 sharesRedeemed) = redeemWithdrawalShares(
            alice,
            withdrawalShares,
            WithdrawalOverrides({
                asBase: true,
                minSlippage: expectedSharePrice,
                extraData: new bytes(0)
            })
        );
        uint256 expectedProceeds = shortAmount.mulDivDown(
            withdrawalShares,
            withdrawalShares + hyperdrive.getPoolConfig().minimumShareReserves
        );
        assertApproxEqAbs(baseProceeds, expectedProceeds, 1e14);
        assertGt(baseProceeds, expectedProceeds);
        assertEq(sharesRedeemed, withdrawalShares);

        // Ensure that a `RedeemWithdrawalShares` event was emitted.
        verifyRedeemWithdrawalSharesEvent(alice, sharesRedeemed, baseProceeds);

        // Ensure that all of the withdrawal shares were burned.
        assertEq(hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID), 0);
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw, 0);
        assertEq(hyperdrive.getPoolInfo().withdrawalSharesProceeds, 0);

        // Ensure that the base proceeds were transferred.
        assertEq(
            baseToken.balanceOf(alice),
            aliceBaseBalanceBefore + baseProceeds
        );
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdriveBaseBalanceBefore - baseProceeds
        );
    }

    function verifyRedeemWithdrawalSharesEvent(
        address provider,
        uint256 expectedSharesRedeemed,
        uint256 expectedBaseProceeds
    ) internal {
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            RedeemWithdrawalShares.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(address(uint160(uint256(log.topics[1]))), provider);
        (uint256 sharesRedeemed, uint256 baseProceeds) = abi.decode(
            log.data,
            (uint256, uint256)
        );
        assertEq(sharesRedeemed, expectedSharesRedeemed);
        assertEq(baseProceeds, expectedBaseProceeds);
    }
}
