// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";
import { MockHyperdrive } from "../../mocks/MockHyperdrive.sol";
import { HyperdriveDataProvider } from "contracts/src/HyperdriveDataProvider.sol";

contract TWAPTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_oracle_write_long() external {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open long
        uint256 baseAmount = 10e18;
        uint256 currentTimestamp = block.timestamp;
        (uint256 maturityTimeFirst, uint256 bondAmountFirst) = openLong(
            bob,
            baseAmount
        );
        // Should have reset the head and the last timestamp
        (uint256 head, uint256 lastTimestamp) = MockHyperdrive(
            address(hyperdrive)
        ).getOracleState();
        assertEq(head, 1);
        assertEq(lastTimestamp, currentTimestamp);

        // Should not reset the head and last timestamp without time advance
        (uint256 maturityTimeSecond, uint256 bondAmountSecond) = openLong(
            bob,
            baseAmount
        );

        (head, lastTimestamp) = MockHyperdrive(address(hyperdrive))
            .getOracleState();
        assertEq(head, 1);
        assertEq(lastTimestamp, currentTimestamp);

        // Advance time
        advanceTime(UPDATE_GAP, int256(apr));

        // Should record a new timestamp
        currentTimestamp = block.timestamp;
        openLong(bob, baseAmount);
        (head, lastTimestamp) = MockHyperdrive(address(hyperdrive))
            .getOracleState();
        assertEq(head, 2);
        assertEq(lastTimestamp, currentTimestamp);

        // Should not record a timestamp on close without advancing time
        closeLong(bob, maturityTimeFirst, bondAmountFirst);
        (head, lastTimestamp) = MockHyperdrive(address(hyperdrive))
            .getOracleState();
        assertEq(head, 2);
        assertEq(lastTimestamp, currentTimestamp);

        // Should advance oracle on close timestamp after time
        advanceTime(UPDATE_GAP, int256(apr));
        currentTimestamp = block.timestamp;
        closeLong(bob, maturityTimeSecond, bondAmountSecond);
        (head, lastTimestamp) = MockHyperdrive(address(hyperdrive))
            .getOracleState();
        assertEq(head, 3);
        assertEq(lastTimestamp, currentTimestamp);
    }

    function test_oracle_write_short() external {
        uint256 apr = 0.05e18;
        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open long
        uint256 baseAmount = 10e18;
        uint256 currentTimestamp = block.timestamp;
        (uint256 maturityTimeFirst, uint256 bondAmountFirst) = openShort(
            bob,
            baseAmount
        );
        // Should have reset the head and the last timestamp
        (uint256 head, uint256 lastTimestamp) = MockHyperdrive(
            address(hyperdrive)
        ).getOracleState();
        assertEq(head, 1);
        assertEq(lastTimestamp, currentTimestamp);

        // Should not reset the head and last timestamp without time advance
        (uint256 maturityTimeSecond, uint256 bondAmountSecond) = openShort(
            bob,
            baseAmount
        );

        (head, lastTimestamp) = MockHyperdrive(address(hyperdrive))
            .getOracleState();
        assertEq(head, 1);
        assertEq(lastTimestamp, currentTimestamp);

        // Advance time
        advanceTime(UPDATE_GAP, int256(apr));

        // Should record a new timestamp
        currentTimestamp = block.timestamp;
        openShort(bob, baseAmount);
        (head, lastTimestamp) = MockHyperdrive(address(hyperdrive))
            .getOracleState();
        assertEq(head, 2);
        assertEq(lastTimestamp, currentTimestamp);

        // Should not record a timestamp on close without advancing time
        closeShort(bob, maturityTimeFirst, bondAmountFirst);
        (head, lastTimestamp) = MockHyperdrive(address(hyperdrive))
            .getOracleState();
        assertEq(head, 2);
        assertEq(lastTimestamp, currentTimestamp);

        // Should advance oracle on close timestamp after time
        advanceTime(UPDATE_GAP, int256(apr));
        currentTimestamp = block.timestamp;
        closeShort(bob, maturityTimeSecond, bondAmountSecond);
        (head, lastTimestamp) = MockHyperdrive(address(hyperdrive))
            .getOracleState();
        assertEq(head, 3);
        assertEq(lastTimestamp, currentTimestamp);
    }

    function recordTwelveDataPoints() internal {
        uint256 apr = 0.05e18;
        for (uint256 i = 1; i <= 12; i++) {
            MockHyperdrive(address(hyperdrive)).recordOracle(i * 1e18);
            advanceTime(UPDATE_GAP, int256(apr));
        }
    }

    function test_oracle_query_reverts() external {
        vm.expectRevert();
        HyperdriveDataProvider(address(hyperdrive)).query(
            block.timestamp + 365 days
        );
    }

    function test_oracle_data_recordings() external {
        // We check that the function properly functions as a buffer
        recordTwelveDataPoints();
        uint256 originalTimestamp = block.timestamp - UPDATE_GAP;
        (uint256 head, uint256 lastTimestamp) = MockHyperdrive(
            address(hyperdrive)
        ).getOracleState();
        assertEq(head, 12 % ORACLE_SIZE);
        assertEq(lastTimestamp, originalTimestamp);

        // Ensure that the time of each update was properly recorded.
        uint256 check = originalTimestamp;
        for (uint256 i = 2; i != 3; i = i == 0 ? 4 : i - 1) {
            (, uint256 time) = MockHyperdrive(address(hyperdrive)).loadOracle(
                i
            );
            assertEq(time, check);
            check -= UPDATE_GAP;
        }

        // Ensure that the query function properly averages the data.
        uint256 period = UPDATE_GAP - 1;
        uint256 finalData = 12;
        uint256 currentData = 12;
        for (uint256 i = 0; i < ORACLE_SIZE - 1; i++) {
            uint256 avg = HyperdriveDataProvider(address(hyperdrive)).query(
                period
            );
            assertEq(avg, (finalData * 1e18 + currentData * 1e18) / 2);

            currentData -= 1;
            period += UPDATE_GAP;
        }
    }
}
