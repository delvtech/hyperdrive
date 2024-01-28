// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";

contract HyperdriveDataProviderTest is HyperdriveTest {
    function testLoadSlots() public {
        uint256[] memory slots = new uint256[](1);
        slots[0] = 8;
        bytes32[] memory values = hyperdrive.load(slots);
        assertEq(address(uint160(uint256(values[0]))), governance);
    }
}
