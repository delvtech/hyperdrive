// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { ForwarderFactory } from "contracts/src/ForwarderFactory.sol";
import { MultiTokenDataProvider } from "contracts/src/MultiTokenDataProvider.sol";
import { MockMultiToken, IMockMultiToken } from "contracts/test/MockMultiToken.sol";
import { BaseTest } from "test/utils/BaseTest.sol";

contract MultiTokenTest is BaseTest {
    IMockMultiToken multiToken;

    function setUp() public override {
        super.setUp();
        vm.startPrank(deployer);
        forwarderFactory = new ForwarderFactory();
        address dataProvider = address(
            new MultiTokenDataProvider(bytes32(0), address(forwarderFactory))
        );

        multiToken = IMockMultiToken(
            address(
                new MockMultiToken(
                    dataProvider,
                    bytes32(0),
                    address(forwarderFactory)
                )
            )
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
