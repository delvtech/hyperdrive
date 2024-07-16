// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { VmSafe } from "forge-std/Vm.sol";
import { BaseTest } from "test/utils/BaseTest.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";
import { IEverlong } from "contracts/src/interfaces/IEverlong.sol";
import { Everlong } from "contracts/src/everlong/Everlong.sol";

contract EverlongTest is HyperdriveTest {
    IEverlong internal everlong;

    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(alice);
        deployEverlong(alice);
    }

    function deployEverlong(address deployer) internal {
        // Deploy the Everlong instance with default underlying, name, and symbol.
        vm.stopPrank();
        vm.startPrank(deployer);
        everlong = IEverlong(
            address(new Everlong(address(hyperdrive), "Everlong Test", "ETEST"))
        );
    }

    function deployEverlong(
        address deployer,
        address underlying,
        string memory name,
        string memory symbol
    ) internal {
        // Deploy the Everlong instance with custom underlying, name, and symbol.
        vm.stopPrank();
        vm.startPrank(deployer);
        everlong = IEverlong(
            address(new Everlong(address(underlying), name, symbol))
        );
    }
}
