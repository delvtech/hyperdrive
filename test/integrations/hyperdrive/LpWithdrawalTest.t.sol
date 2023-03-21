// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";

contract LpWithdrawalTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_lp_withdrawal_immediate_redemption(
        uint128 basePaid
    ) external {
        uint256 apr = 0.05e18;
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

        // TODO: Think more about the implications of this. This is effectively
        // allowing LPs to rug traders on slippage.
        //
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
}
