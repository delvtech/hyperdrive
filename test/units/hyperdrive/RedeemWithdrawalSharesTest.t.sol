// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { VmSafe } from "forge-std/Vm.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract RedeemWithdrawalSharesTest is HyperdriveTest {
    using FixedPointMath for uint256;
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
        vm.expectRevert(Errors.OutputLimit.selector);
        uint256 expectedOutputPerShare = shortAmount.divDown(withdrawalShares);
        hyperdrive.redeemWithdrawalShares(
            withdrawalShares,
            2 * expectedOutputPerShare,
            alice,
            true
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

        // Alice redeems her withdrawal shares.
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );
        (uint256 baseProceeds, uint256 sharesRedeemed) = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertEq(baseProceeds, shortAmount);
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

        // Alice redeems half of her withdrawal shares.
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );
        (uint256 baseProceeds, uint256 sharesRedeemed) = redeemWithdrawalShares(
            alice,
            withdrawalShares / 2
        );
        assertApproxEqAbs(baseProceeds, shortAmount / 2, 1);
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
        assertApproxEqAbs(baseProceeds, shortAmount / 2, 1);
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
        uint256 lpShares = initialize(alice, 0.02e18, 500_000_000e18);

        // Bob opens a large long.
        (uint256 maturityTime, uint256 longAmount) = openLong(
            bob,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );

        // Alice removes her liquidity.
        (, uint256 withdrawalShares) = removeLiquidity(alice, lpShares);

        // The term passes and no interest accrues.
        advanceTime(POSITION_DURATION / 2, 0);

        // Bob closes his long.
        uint256 longBaseProceeds = closeLong(bob, maturityTime, longAmount);

        // Alice redeems her withdrawal shares.
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );
        (uint256 baseProceeds, uint256 sharesRedeemed) = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertEq(baseProceeds, longAmount - longBaseProceeds);
        assertEq(sharesRedeemed, withdrawalShares);

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

        // Alice redeems her withdrawal shares.
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );
        uint256 expectedSharePrice = shortAmount.divDown(withdrawalShares);
        (uint256 baseProceeds, uint256 sharesRedeemed) = redeemWithdrawalShares(
            alice,
            withdrawalShares,
            expectedSharePrice
        );
        assertEq(baseProceeds, shortAmount);
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
