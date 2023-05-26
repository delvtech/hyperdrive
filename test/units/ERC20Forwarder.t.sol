// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { ForwarderFactory } from "contracts/src/ForwarderFactory.sol";
import { ERC20Forwarder } from "contracts/src/ERC20Forwarder.sol";
import { IMultiToken } from "contracts/src/interfaces/IMultiToken.sol";
import { MultiTokenDataProvider } from "contracts/src/MultiTokenDataProvider.sol";
import { MockMultiToken, IMockMultiToken } from "contracts/test/MockMultiToken.sol";
import { BaseTest } from "test/utils/BaseTest.sol";

contract ERC20ForwarderFactoryTest is BaseTest {
    IMockMultiToken multiToken;

    function setUp() public override {
        super.setUp();
        vm.startPrank(deployer);
        forwarderFactory = new ForwarderFactory();
        bytes32 codeHash = keccak256(type(ERC20Forwarder).creationCode);
        address dataProvider = address(
            new MultiTokenDataProvider(codeHash, address(forwarderFactory))
        );
        multiToken = IMockMultiToken(
            address(
                new MockMultiToken(
                    dataProvider,
                    codeHash,
                    address(forwarderFactory)
                )
            )
        );
        vm.stopPrank();
    }

    function testForwarderFactory() public {
        (IMultiToken token, uint256 tokenID) = forwarderFactory.getDeployDetails();
        assertEq(address(token), address((IMultiToken(address(1)))));
        assertEq(tokenID, 1);

        ERC20Forwarder forwarder = forwarderFactory.create(multiToken, 5);

        // Transient variable should be reset after each create
        (token, tokenID) = forwarderFactory.getDeployDetails();
        assertEq(address(token), address((IMultiToken(address(1)))));
        assertEq(tokenID, 1);

        address retrievedForwarder = forwarderFactory.getForwarder(multiToken, 5);

        assertEq(address(forwarder), retrievedForwarder);
    }

    // Test Forwarder contract
    function testForwarderMetadata() public {
        ERC20Forwarder forwarder = forwarderFactory.create(multiToken, 5);
        assertEq(forwarder.decimals(), 18);

        vm.startPrank(alice);
        multiToken.__setNameAndSymbol(5, "Token", "TKN");
        vm.stopPrank();

        assertEq(forwarder.name(), "Token");
        assertEq(forwarder.symbol(), "TKN");
    }

    function testForwarderERC20() public {
        uint256 AMOUNT = 10000 ether;
        uint256 TOKENID = 8;
        ERC20Forwarder forwarder = forwarderFactory.create(multiToken, TOKENID);

        multiToken.mint(TOKENID, alice, AMOUNT);

        assertEq(forwarder.balanceOf(address(alice)), AMOUNT);
        assertEq(forwarder.totalSupply(), AMOUNT);
        
        vm.startPrank(alice);
        forwarder.approve(bob, AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(bob);
        forwarder.transferFrom(alice, bob, AMOUNT);
        vm.stopPrank();
        
        assertEq(forwarder.balanceOf(address(alice)), 0);
        assertEq(forwarder.balanceOf(address(bob)), AMOUNT);

        assertEq(forwarder.totalSupply(), AMOUNT);
    }
}