// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";

// FIXME: Some scenarios that we need to test.
//
// - [ ] Short trade closed immediately.
// - [ ] Short trade closed at redemption.
// - [ ] A mixture of long and short trades.
// - [ ] LPs with different long and short weightings.
contract LpWithdrawalTest is HyperdriveTest {
    // FIXME
    using Lib for uint256;
    using FixedPointMath for uint256;

    function test_lp_withdrawal_long_immediate_close(
        uint128 basePaid
    ) external {
        uint256 apr = 0.02e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Bob opens a max long.
        vm.assume(
            basePaid >= 0.001e18 &&
                basePaid <= HyperdriveUtils.calculateMaxOpenLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Alice removes all of her LP shares.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        assertEq(baseProceeds, contribution - (longAmount - basePaid));
        assertEq(withdrawalShares, longAmount - basePaid);

        // Bob closes his long. He will pay quite a bit of slippage on account
        // of the LP's removed liquidity.
        uint256 longProceeds = closeLong(bob, maturityTime, longAmount);
        assertGt(basePaid - longProceeds, withdrawalShares.mulDivDown(3, 4));

        // Alice redeems her withdrawal shares. She receives the unlocked margin
        // as well as quite a bit of "interest" that was collected from Bob's
        // slippage.
        uint256 withdrawalProceeds = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        assertEq(
            withdrawalProceeds,
            withdrawalShares + (basePaid - longProceeds)
        );

        // Ensure that the ending base balance of Hyperdrive is zero.
        assertEq(baseToken.balanceOf(address(hyperdrive)), 0);
    }

    // FIXME: We should also test that the withdrawal shares receive interest
    // if the long isn't closed immediately.
    function test_lp_withdrawal_long_redemption(
        uint128 basePaid,
        int64 variableApr
    ) external {
        uint256 apr = 0.02e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Bob opens a max long.
        vm.assume(
            basePaid >= 0.001e18 &&
                basePaid <= HyperdriveUtils.calculateMaxOpenLong(hyperdrive)
        );
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Alice removes all of her LP shares.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        assertEq(baseProceeds, contribution - (longAmount - basePaid));
        assertEq(withdrawalShares, longAmount - basePaid);

        // Positive interest accrues over the term. We create a checkpoint for
        // the first checkpoint after opening the long to ensure that the
        // withdrawal shares will be accounted for properly.
        vm.assume(variableApr >= 0 && variableApr <= 2e18);
        advanceTime(CHECKPOINT_DURATION, variableApr);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));
        advanceTime(POSITION_DURATION - CHECKPOINT_DURATION, variableApr);

        // Bob closes his long. He should receive the full bond amount since he
        // is closing at maturity.
        uint256 longProceeds = closeLong(bob, maturityTime, longAmount);
        assertApproxEqAbs(longProceeds, longAmount, 1e10);

        // Alice redeems her withdrawal shares. She receives the interest
        // collected on the capital underlying the long for .
        uint256 withdrawalProceeds = redeemWithdrawalShares(
            alice,
            withdrawalShares
        );
        (, int256 interest) = HyperdriveUtils.calculateCompoundInterest(
            longAmount,
            variableApr,
            POSITION_DURATION - CHECKPOINT_DURATION
        );
        assertApproxEqAbs(withdrawalProceeds, uint256(interest), 1e10);

        // Ensure that the ending base balance of Hyperdrive is zero.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            0,
            100_000e18
        );
        assertApproxEqAbs(
            hyperdrive.totalSupply(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
            ),
            0,
            1e10
        );
    }
}
