// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";

// FIXME: Remove this test and consider adding
contract HyperdriveDataProviderTest is HyperdriveTest {
    function testLoadSlots() public {
        uint256[] memory slots = new uint256[](1);
        slots[0] = 15;
        bytes32[] memory values = hyperdrive.load(slots);
        assertEq(address(uint160(uint256(values[0]))), governance);
    }
}
