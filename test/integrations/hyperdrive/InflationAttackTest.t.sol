// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { HyperdriveTest, HyperdriveUtils } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract InflationAttackTest is HyperdriveTest {
    using Lib for *;

    // TODO: This test is currently failing. If the share price is larger
    // than the initial share price, then the pool can't be initialized.
    // We should consider using a factory deployment pattern or initializing
    // on construction.
    //
    // This test ensures that a malicious user cannot drain the pool by
    // donating base to the pool before initialization.
    function test_inflation_attack_before_initialization(
        uint256 contribution,
        uint256 donation
    ) internal {
        // Ensure that the testing parameters are within bounds.
        contribution = contribution.normalizeToRange(1e18, 10_000_000e18);
        donation = donation.normalizeToRange(0, 10_000_000e18);

        // A malicious donation is made to the pool.
        vm.stopPrank();
        vm.startPrank(bob);
        baseToken.mint(address(hyperdrive), donation);

        // Initialize the pool.
        uint256 lpShares = initialize(alice, 0.02e18, contribution);

        // Ensure that the initial contribution is returned.
        (uint256 baseProceeds, ) = removeLiquidity(alice, lpShares);
        assertApproxEqAbs(baseProceeds, contribution, 1e18);
    }

    // This test ensures that a malicious user cannot steal from an LP adding
    // liquidity by inflating the assets of the pool.
    function test_inflation_attack_add_liquidity(
        uint256 contribution,
        uint256 donation
    ) external {
        // Ensure that the testing parameters are within bounds.
        contribution = contribution.normalizeToRange(1e18, 10_000_000_000e18);
        donation = donation.normalizeToRange(0, 10_000_000e18);

        // Initialize the pool.
        uint256 initialContribution = 1;
        initialize(alice, 0.02e18, initialContribution);
        assertEq(hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice), 1);

        // A malicious donation is made to the pool.
        vm.stopPrank();
        vm.startPrank(alice);
        baseToken.mint(address(hyperdrive), donation);

        // Bob adds liquidity.
        uint256 lpShares = addLiquidity(bob, contribution);

        // Ensure that Alice can withdraw almost all of her base.
        (uint256 baseProceeds, ) = removeLiquidity(bob, lpShares);
        assertApproxEqAbs(baseProceeds, contribution, 1e18);
    }

    // This test ensures that a malicious user cannot steal from an LP removing
    // liquidity by inflating the assets of the pool.
    function test_inflation_attack_remove_liquidity(
        uint256 contribution,
        uint256 donation
    ) external {
        // Ensure that the testing parameters are within bounds.
        contribution = contribution.normalizeToRange(1e18, 10_000_000_000e18);
        donation = donation.normalizeToRange(0, 10_000_000e18);

        // Initialize the pool.
        uint256 lpShares = initialize(alice, 0.02e18, contribution);

        // A malicious donation is made to the pool.
        vm.stopPrank();
        vm.startPrank(alice);
        baseToken.mint(address(hyperdrive), donation);

        // Ensure that Alice's withdrawal proceeds are greater than or equal
        // to her contribution.
        (uint256 baseProceeds, ) = removeLiquidity(alice, lpShares);
        assertGe(baseProceeds, contribution);
    }

    // This test ensures that a malicious user cannot steal from a long on open
    // by inflating the assets of the pool.
    function test_inflation_attack_open_long() external {
        // Initialize the pool with one wei.
        initialize(alice, 0.02e18, 1);

        // A malicious donation is made to the pool. This donation is comically
        // large to highlight the fact that the long flow is resilient to
        // inflation attacks.
        vm.stopPrank();
        vm.startPrank(alice);
        baseToken.mint(address(hyperdrive), 100_000_000_000e18);

        // Bob opens a long.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 basePaid = 10e18;
        baseToken.mint(basePaid);
        baseToken.approve(address(hyperdrive), basePaid);
        vm.expectRevert(Errors.FixedPointMath_SubOverflow.selector);
        hyperdrive.openLong(basePaid, 0, bob, true);
    }

    // This test ensures that a malicious user cannot steal from a long by
    // inflating the assets of the pool.
    function test_inflation_attack_close_long() external {
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, 0.02e18, contribution);

        // Bob opens a long.
        uint256 basePaid = 10_000_000e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // A malicious donation is made to the pool. This donation is comically
        // large to highlight the fact that the long flow is resilient to
        // inflation attacks.
        vm.stopPrank();
        vm.startPrank(alice);
        baseToken.mint(address(hyperdrive), 100_000_000_000e18);

        // Bob closes the long. Bob should receive a small benefit from the sale.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);
        assertGt(baseProceeds, basePaid);
        assertLt(baseProceeds, bondAmount);

        // Bob opens a long.
        basePaid = 10_000_000e18;
        (maturityTime, bondAmount) = openLong(bob, basePaid);

        // Time passes and interest accrues.
        uint256 variableRate = 0.2e18;
        advanceTime(POSITION_DURATION, int256(variableRate));

        // A malicious donation is made to the pool. This donation is comically
        // large to highlight the fact that the long flow is resilient to
        // inflation attacks.
        vm.stopPrank();
        vm.startPrank(alice);
        baseToken.mint(address(hyperdrive), 100_000_000_000e18);

        // Bob redeems the long. He should receive the bond amount.
        baseProceeds = closeLong(bob, maturityTime, bondAmount);
        assertApproxEqAbs(baseProceeds, bondAmount, 500);

        // Alice removes her liquidity. She should receive more than her
        // original contribution plus interest.
        (uint256 contributionPlusInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(
                contribution,
                0.02e18,
                POSITION_DURATION
            );
        (uint256 withdrawalProceeds, ) = removeLiquidity(alice, lpShares);
        assertGt(withdrawalProceeds, contributionPlusInterest);
    }

    // This test ensures that a malicious user cannot steal from a short on open
    // by inflating the assets of the pool.
    function test_inflation_attack_open_short() external {
        // Initialize the pool with one wei.
        initialize(alice, 0.02e18, 1);

        // A malicious donation is made to the pool. This donation is comically
        // large to highlight the fact that the long flow is resilient to
        // inflation attacks.
        vm.stopPrank();
        vm.startPrank(alice);
        baseToken.mint(address(hyperdrive), 100_000_000_000e18);

        // Bob opens a short.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = 10e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        vm.expectRevert(Errors.FixedPointMath_SubOverflow.selector);
        hyperdrive.openShort(bondAmount, type(uint256).max, bob, true);
    }

    // This test ensures that a malicious user cannot steal from a short by
    // inflating the assets of the pool.
    function test_inflation_attack_close_short() external {
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, 0.02e18, contribution);

        // Bob opens a short.
        uint256 bondAmount = 10_000_000e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, bondAmount);

        // A malicious donation is made to the pool. This donation is comically
        // large to highlight the fact that the long flow is resilient to
        // inflation attacks.
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 donation = 100_000_000_000e18;
        baseToken.mint(address(hyperdrive), donation);

        // Bob closes the short. Bob should receive a benefit from the sale
        // because the share price is inflated.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);
        assertGt(baseProceeds, basePaid);

        // TODO: Investigate this more. How much of a donation is needed to make
        // reasonably sized shorts impractical? We should reconsider whether or
        // not there is a way to avoid having backpaid interest. We should test
        // this edge case in the context of negative interest where the short
        // could lose some of this backpaid interest.
        //
        // Bob opens a short. Due to the massive inflation in the share
        // price, the short must backpay more interest than the bond amount.
        // They will get this back upon closing. If they just waited until the
        // next checkpoint, this wouldn't be a problem.
        bondAmount = 10_000_000e18;
        (maturityTime, basePaid) = openShort(bob, bondAmount, bondAmount * 200);

        // Time passes and interest accrues.
        uint256 variableRate = 0.2e18;
        advanceTime(POSITION_DURATION, int256(variableRate));

        // A malicious donation is made to the pool. This donation is comically
        // large to highlight the fact that the short flow is resilient to
        // inflation attacks.
        vm.stopPrank();
        vm.startPrank(alice);
        donation = 100_000_000_000e18;
        baseToken.mint(address(hyperdrive), donation);

        // Bob redeems the short. He should receive more than the interest
        // accrued on the short because the share price is inflated by the
        // attack.
        (uint256 bondAmountPlusInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(
                bondAmount,
                int256(variableRate),
                POSITION_DURATION
            );
        baseProceeds = closeShort(bob, maturityTime, bondAmount);
        assertGt(baseProceeds, bondAmountPlusInterest);

        // Alice removes her liquidity. She should receive more than her
        // original contribution plus interest.
        (uint256 contributionPlusInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(
                contribution,
                0.02e18,
                POSITION_DURATION
            );
        (uint256 withdrawalProceeds, ) = removeLiquidity(alice, lpShares);
        assertGt(withdrawalProceeds, contributionPlusInterest);
    }
}
