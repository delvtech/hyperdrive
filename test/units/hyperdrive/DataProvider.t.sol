// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";

contract HyperdriveDataProviderTest is HyperdriveTest {
    function testLoadSlots() public view {
        uint256[] memory slots = new uint256[](1);
        slots[0] = 9;
        bytes32[] memory values = hyperdrive.load(slots);
        assertEq(address(uint160(uint256(values[0]))), governance);
    }
}
