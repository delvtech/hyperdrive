// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { MockHyperdriveMath } from "contracts/test/MockHyperdriveMath.sol";

contract MockHyperdriveMathScript is Script {
    function setUp() external {}

    function run() external {
        vm.startBroadcast();

        MockHyperdriveMath mockHyperdriveMath = new MockHyperdriveMath();

        vm.stopBroadcast();

        console.log(
            "Deployed MockHyperdriveMath to: %s",
            address(mockHyperdriveMath)
        );
    }
}
