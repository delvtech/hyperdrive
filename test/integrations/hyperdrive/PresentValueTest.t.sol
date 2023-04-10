// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import { Lib } from "test/utils/Lib.sol";

import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";

contract PresentValueTest is HyperdriveTest {
    using Lib for *;
    using FixedPointMath for *;

    // FIXME:
    // - Test different combinations of trades
    // - Test with fees
    function test_present_value_example() external {
        initialize(alice, 0.02e18, 500_000_000e18);

        console.log("presentValue: %s", presentValue().toString(18));

        // Time advances and value accrues.
        advanceTime(POSITION_DURATION, 0.2e18);

        console.log("presentValue: %s", presentValue().toString(18));

        // Open and close a short
        console.log("open and close a short - dt = 0");
        {
            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime, ) = openShort(alice, shortAmount);
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log("presentValue: %s", presentValue().toString(18));
        }

        // Open and close a long
        console.log("open and close a long - dt = 0");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 maturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the long position.
            closeLong(alice, maturityTime, longAmount);
            console.log("presentValue: %s", presentValue().toString(18));
        }

        // Open a long and a short
        console.log("open and close a long and a short - dt = 0");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log("presentValue: %s", presentValue().toString(18));

            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 shortMaturityTime, ) = openShort(alice, shortAmount);
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount);
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the short position.
            closeShort(alice, shortMaturityTime, shortAmount);
            console.log("presentValue: %s", presentValue().toString(18));
        }

        // Open a long and close after some time
        console.log("open and close a long - dt = 0.5");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 maturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log("presentValue: %s", presentValue().toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the long position.
            closeLong(alice, maturityTime, longAmount);
            console.log("presentValue: %s", presentValue().toString(18));
        }

        // FIXME: Why does the present value decrease over this period?
        //
        // Open a long and close after some time
        console.log("open and close a short - dt = 0.5");
        {
            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime, ) = openShort(alice, shortAmount);
            console.log("presentValue: %s", presentValue().toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log("presentValue: %s", presentValue().toString(18));
        }

        // Open a long and a short and close after some time
        console.log("open and close a long and short - dt = 0.5");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log("presentValue: %s", presentValue().toString(18));

            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime, ) = openShort(alice, shortAmount);
            console.log("presentValue: %s", presentValue().toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount);
            console.log("presentValue: %s", presentValue().toString(18));
        }

        // Open a long and a short and close after some time
        console.log("open and close a long and short - dt = 0.75");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log("presentValue: %s", presentValue().toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 4, 0.2e18);
            console.log("presentValue: %s", presentValue().toString(18));

            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime, ) = openShort(alice, shortAmount);
            console.log("presentValue: %s", presentValue().toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount);
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount);
            console.log("presentValue: %s", presentValue().toString(18));
        }

        // FIXME: This shows a large problem in the calculation of maturity time.
        //
        // Open a long and a short and close after some time. The close will be
        // broken up into several trades.
        console.log("open and close a long and short - dt = 0.5");
        {
            // Open a long position.
            uint256 longPaid = 10_000_000e18;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                alice,
                longPaid
            );
            console.log("presentValue: %s", presentValue().toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 4, 0.2e18);
            console.log("presentValue: %s", presentValue().toString(18));

            // Open a short position.
            uint256 shortAmount = 10_000_000e18;
            (uint256 maturityTime, ) = openShort(alice, shortAmount);
            console.log("presentValue: %s", presentValue().toString(18));

            // Advance time.
            advanceTime(POSITION_DURATION / 2, 0.2e18);
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount / 2);
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount / 2);
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the short position.
            closeShort(alice, maturityTime, shortAmount / 2);
            console.log("presentValue: %s", presentValue().toString(18));

            // Close the long position.
            closeLong(alice, longMaturityTime, longAmount / 2 - 1e18);
            console.log("presentValue: %s", presentValue().toString(18));
            closeLong(alice, longMaturityTime, 1e18);
        }

        // FIXME: Test with different amounts of time elapsed.
    }

    function presentValue() internal view returns (uint256) {
        return
            HyperdriveMath.calculatePresentValue(
                hyperdrive.getPoolInfo().shareReserves,
                hyperdrive.getPoolInfo().bondReserves,
                hyperdrive.getPoolInfo().sharePrice,
                hyperdrive.getPoolConfig().initialSharePrice,
                hyperdrive.getPoolConfig().timeStretch,
                hyperdrive.getPoolInfo().longsOutstanding,
                HyperdriveUtils.calculateTimeRemaining(
                    hyperdrive,
                    uint256(hyperdrive.getPoolInfo().longAverageMaturityTime)
                        .divUp(1e36)
                ),
                hyperdrive.getPoolInfo().shortsOutstanding,
                HyperdriveUtils.calculateTimeRemaining(
                    hyperdrive,
                    uint256(hyperdrive.getPoolInfo().shortAverageMaturityTime)
                        .divUp(1e36)
                )
            );
    }
}
