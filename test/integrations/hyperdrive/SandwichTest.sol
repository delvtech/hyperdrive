// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "contracts/libraries/FixedPointMath.sol";
import "../../utils/HyperdriveTest.sol";

contract SandwichTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_sandwich_test_trades(uint8 _apr, uint64 _timeDelta) external {
        uint256 apr = uint256(_apr) * 0.01e18;
        uint256 timeDelta = uint256(_timeDelta);
        vm.assume(apr >= 0.005e18 && apr <= 0.2e18);
        vm.assume(timeDelta <= FixedPointMath.ONE_18 && timeDelta >= 0);

        // Deploy the pool with fees.
        {
            uint256 timeStretchApr = 0.02e18;
            uint256 curveFee = 0.1e18;
            deploy(alice, timeStretchApr, curveFee, 0);
        }

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
        vm.warp(block.timestamp + POSITION_DURATION.mulDown(timeDelta));
        hyperdrive.setSharePrice(
            getPoolInfo().sharePrice.mulDown(
                FixedPointMath.ONE_18 + apr.mulDown(timeDelta)
            )
        );

        // Celine opens a short.
        uint256 shortAmount = 200_000_000e18;
        (uint256 shortMaturitytime, ) = openShort(celine, shortAmount);

        // Bob closes his long.
        closeLong(bob, longMaturityTime, longAmount);

        // Celine immediately closes her short.
        closeShort(celine, shortMaturitytime, shortAmount);

        // Ensure the proceeds from the sandwich attack didn't negatively
        // impact the LP. With this in mind, they should have made at least as
        // much money as if no trades had been made and they just collected
        // variable APR.
        uint256 lpProceeds = removeLiquidity(alice, lpShares);
        assertGe(
            lpProceeds,
            calculateFutureValue(contribution, apr, timeDelta)
        );
    }
}
