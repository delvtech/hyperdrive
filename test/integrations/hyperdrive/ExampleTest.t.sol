// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { console2 as console } from "forge-std/console2.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";

contract ExampleTest {
    function test_example() external {
        console.log(HyperdriveUtils.decodeError(bytes4(0x4e487b71)));
    }
}
