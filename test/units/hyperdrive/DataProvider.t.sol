// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { MockHyperdrive } from "../../../contracts/test/MockHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

contract HyperdriveDataProviderTest is HyperdriveTest {
    function testLoadSlots() external {
        // Set several values in the market state.
        IHyperdrive.MarketState memory marketState;
        uint256 shareReserves = 12345;
        marketState.shareReserves = uint128(shareReserves);
        uint256 longExposure = 54321;
        marketState.longExposure = uint128(longExposure);
        MockHyperdrive(address(hyperdrive)).setMarketState(marketState);

        // Get several of the slots and ensure that they are equal to the
        // values that were set.
        uint256[] memory slots = new uint256[](2);
        slots[0] = 2;
        slots[1] = 3;
        bytes32[] memory values = hyperdrive.load(slots);
        assertEq(uint256(values[0]), shareReserves);
        assertEq(uint256(values[1]), longExposure);
    }
}
