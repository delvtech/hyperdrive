// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdJson } from "forge-std/StdJson.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { MockHyperdriveMath } from "contracts/test/MockHyperdriveMath.sol";

contract MockHyperdriveMathScript is Script {
    using stdJson for string;

    function setUp() external {}

    function run() external {
        vm.startBroadcast();

        MockHyperdriveMath mockHyperdriveMath = new MockHyperdriveMath();

        vm.stopBroadcast();

        string memory result = "result";
        result = vm.serializeAddress(
            result,
            "mockHyperdriveMath",
            address(mockHyperdriveMath)
        );
        result.write("./artifacts/script_addresses.json");
    }
}
