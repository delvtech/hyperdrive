// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Hyperdrive.sol";

contract HyperdriveTest is Test {
    Hyperdrive public hyperdrive;

    function setUp() public {
        hyperdrive = new Hyperdrive();
    }
}
