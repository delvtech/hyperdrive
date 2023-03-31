// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";

contract DonationAttackTest is HyperdriveTest {
    // This test ensures that a malicious user cannot drain the pool by
    // donating base to the pool and then removing all of their liquidity.
    function test_donation_attack(
        uint256 contribution,
        uint256 donation
    ) external {
        // Ensure that the testing parameters are within bounds.
        contribution = (contribution % (10_000_000_000e18 - 1e18)) + 1e18;
        donation = donation % 10_000_000_000e18;

        // Initialize Hyperdrive with a small amount of base.
        uint256 initialContribution = 1e18;
        initialize(alice, 0.02e18, initialContribution);

        // Donate 1 base to the pool.
        vm.stopPrank();
        vm.startPrank(alice);
        baseToken.mint(address(hyperdrive), donation);

        // Bob adds 1 base of liquidity.
        uint256 bobLpShares = addLiquidity(bob, contribution);

        // Ensure that Bob can remove all but a dust amount of his base.
        (uint256 baseProceeds, ) = removeLiquidity(bob, bobLpShares);
        assertApproxEqAbs(baseProceeds, contribution, 1e11);
    }
}
