// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { HyperdriveTest } from "./Test.sol";

contract HyperdriveScenarioTest is HyperdriveTest {
    function setUp() public override {
        super.setUp();
    }

    function test_initialize() public {
        show();
        vm.startPrank(alice);

        hyperdrive.initialize(1000e18, 0.05e18);
        vm.stopPrank();
        show();


    }
}
