// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { BaseTest } from "test/utils/BaseTest.sol";
import { MockMultiToken } from "contracts/test/MockMultiToken.sol";
import { ForwarderFactory } from "contracts/src/ForwarderFactory.sol";

contract MultiTokenTest is BaseTest {
    MockMultiToken multiToken;

    function setUp() public override {
        super.setUp();
        vm.startPrank(deployer);
        forwarderFactory = new ForwarderFactory();
        // FIXME: Use a real data provider.
        multiToken = new MockMultiToken(
            address(0),
            bytes32(0),
            address(forwarderFactory)
        );
        vm.stopPrank();
    }

    function test__name_symbol() public {
        vm.startPrank(alice);
        multiToken.__setNameAndSymbol(5, "Token", "TKN");
        vm.stopPrank();
        assertEq(multiToken.name(5), "Token");
        assertEq(multiToken.symbol(5), "TKN");
    }
}
