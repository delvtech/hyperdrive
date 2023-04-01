// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract InflationAttackTest is HyperdriveTest {
    using Lib for *;

    // TODO: This test is currently failing. If the share price is larger
    // than the initial share price, then the pool can't be initialized.
    //
    // This test ensures that a malicious user cannot drain the pool by
    // donating base to the pool before initialization.
    function test_inflation_attack_before_initialization(
        uint256 contribution,
        uint256 donation
    ) external {
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

    // This test ensures that a malicious user cannot drain the pool by
    // donating base to the pool and then removing all of their liquidity.
    function test_inflation_attack_after_initialization(
        uint256 contribution,
        uint256 donation
    ) external {
        // Ensure that the testing parameters are within bounds.
        contribution = contribution.normalizeToRange(1e18, 10_000_000_000e18);
        donation = donation.normalizeToRange(0, 10_000_000e18);

        // Initialize the pool.
        uint256 initialContribution = 1;
        initialize(alice, 0.02e18, initialContribution);

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
}
