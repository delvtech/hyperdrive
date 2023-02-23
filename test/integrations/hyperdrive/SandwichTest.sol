// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

// FIXME
import "forge-std/console.sol";

import "contracts/libraries/FixedPointMath.sol";
import "../../utils/HyperdriveTest.sol";

contract SandwichTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_sandwich_test_trades() external {
        uint256 apr = 0.01e18;
        deploy(alice, apr, 0.01e18, 0);

        // Initialize the market.
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Bob opens a long.
        uint256 longPaid = 50_000_000e18;
        (uint256 longMaturityTime, uint256 longAmount) = openLong(
            bob,
            longPaid
        );

        // Some of the term passes and interest accrues at the starting APR.
        uint256 timeDelta = 1e18;
        vm.warp(block.timestamp + POSITION_DURATION.mulDown(timeDelta));
        hyperdrive.setSharePrice(
            getPoolInfo().sharePrice.mulDown(
                FixedPointMath.ONE_18 + apr.mulDown(timeDelta)
            )
        );

        // Celine opens a short.
        uint256 shortAmount = 200_000_000e18;
        (uint256 shortMaturitytime, uint256 shortPaid) = openShort(
            celine,
            shortAmount
        );

        // Bob closes his long.
        uint256 longProceeds = closeLong(bob, longMaturityTime, longAmount);

        // Celine immediately closes her short. She shouldn't have made a profit.
        uint256 shortProceeds = closeShort(
            celine,
            shortMaturitytime,
            shortAmount
        );
        assertLe(shortProceeds, shortPaid);

        // FIXME: This isn't a good enough check.
        //
        // Alice burns her LP shares. She should end up with more money than she
        // started with.
        uint256 lpProceeds = removeLiquidity(alice, lpShares);
        assertGe(
            lpProceeds,
            calculateFutureValue(contribution, apr, timeDelta)
        );
    }
}
