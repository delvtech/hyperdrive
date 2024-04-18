// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { HyperdriveRegistry } from "contracts/src/factory/HyperdriveRegistry.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { Lib } from "test/utils/Lib.sol";

contract HyperdriveRegistryTests is Test {
    using Lib for *;

    string internal constant NAME = "HyperdriveRegistry";

    HyperdriveRegistry registry;

    function setUp() external {
        registry = new HyperdriveRegistry(NAME);
    }

    function test_name() public view {
        assert(registry.name().eq(NAME));
    }

    function test_version() public view {
        assert(registry.version().eq("v1.0.0"));
    }

    function test_updateGovernance_noAuth() public {
        address notAdmin = makeAddr("notAdmin");

        vm.prank(notAdmin);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        registry.updateGovernance(makeAddr("newGovernance"));
    }

    function test_updateGovernance() public {
        address newGovernance = makeAddr("newGovernance");

        assertEq(registry.governance(), address(this));

        registry.updateGovernance(newGovernance);

        assertEq(registry.governance(), newGovernance);
    }

    function test_setHyperdriveInfo_noAuth() public {
        address notAdmin = makeAddr("notAdmin");

        vm.prank(notAdmin);
        vm.expectRevert(IHyperdrive.Unauthorized.selector);
        registry.setHyperdriveInfo(makeAddr("hyperdrive"), 0);
    }

    function test_setHyperdriveInfo() public {
        address hyperdrive = makeAddr("hyperdrive");

        assertEq(registry.getHyperdriveInfo(hyperdrive), 0);

        registry.setHyperdriveInfo(hyperdrive, 1);

        assertEq(registry.getHyperdriveInfo(hyperdrive), 1);
    }

    function test_getHyperdriveInfo() public {
        address hyperdrive1 = makeAddr("hyperdrive1");
        address hyperdrive2 = makeAddr("hyperdrive2");

        assertEq(registry.getHyperdriveInfo(hyperdrive1), 0);
        assertEq(registry.getHyperdriveInfo(hyperdrive2), 0);

        registry.setHyperdriveInfo(hyperdrive1, 1);
        registry.setHyperdriveInfo(hyperdrive2, 2);

        assertEq(registry.getHyperdriveInfo(hyperdrive1), 1);
        assertEq(registry.getHyperdriveInfo(hyperdrive2), 2);
    }
}
