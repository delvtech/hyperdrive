// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20Forwarder } from "../../contracts/src/interfaces/IERC20Forwarder.sol";
import { IERC20ForwarderFactory } from "../../contracts/src/interfaces/IERC20ForwarderFactory.sol";
import { IMultiToken } from "../../contracts/src/interfaces/IMultiToken.sol";
import { AssetId } from "../../contracts/src/libraries/AssetId.sol";
import { ERC20Forwarder } from "../../contracts/src/token/ERC20Forwarder.sol";
import { ERC20ForwarderFactory } from "../../contracts/src/token/ERC20ForwarderFactory.sol";
import { MockAssetId } from "../../contracts/test/MockAssetId.sol";
import { IMockHyperdrive } from "../../contracts/test/MockHyperdrive.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { Lib } from "../utils/Lib.sol";

contract DummyForwarderFactory is ERC20ForwarderFactory {
    constructor() ERC20ForwarderFactory("ForwarderFactory") {}

    function getForwarder(
        IMultiToken, // unused
        uint256 // unused
    ) public pure override returns (address) {
        return address(0);
    }
}

contract ERC20ForwarderFactoryTest is HyperdriveTest {
    using Lib for *;

    IERC20Forwarder forwarder;

    function setUp() public override {
        super.setUp();

        // Deploy the forwarder
        vm.startPrank(deployer);

        forwarder = forwarderFactory.create(
            IMultiToken(address(hyperdrive)),
            9
        );

        vm.stopPrank();
    }

    function testERC20ForwarderFactory() public {
        (IMultiToken token, uint256 tokenID) = forwarderFactory
            .getDeployDetails();
        assertEq(address(token), address((IMultiToken(address(1)))));
        assertEq(tokenID, 1);

        forwarder = forwarderFactory.create(
            IMultiToken(address(hyperdrive)),
            5
        );

        // Transient variable should be reset after each create
        (token, tokenID) = forwarderFactory.getDeployDetails();
        assertEq(address(token), address((IMultiToken(address(1)))));
        assertEq(tokenID, 1);

        address retrievedForwarder = forwarderFactory.getForwarder(
            IMultiToken(address(hyperdrive)),
            5
        );

        assertEq(address(forwarder), retrievedForwarder);
    }

    function testERC20ForwarderFactoryInvalidForwarderAddress() public {
        DummyForwarderFactory forwarderFactory = new DummyForwarderFactory();
        vm.expectRevert(
            IERC20ForwarderFactory.InvalidForwarderAddress.selector
        );
        forwarder = forwarderFactory.create(
            IMultiToken(address(hyperdrive)),
            5
        );
    }
}
