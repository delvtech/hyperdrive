// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20Forwarder } from "contracts/src/interfaces/IERC20Forwarder.sol";
import { IMultiToken } from "contracts/src/interfaces/IMultiToken.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ERC20Forwarder } from "contracts/src/token/ERC20Forwarder.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { MockAssetId } from "contracts/test/MockAssetId.sol";
import { MockMultiToken, IMockMultiToken } from "contracts/test/MockMultiToken.sol";
import { BaseTest } from "test/utils/BaseTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract ERC20ERC20ForwarderFactoryTest is BaseTest {
    using Lib for *;

    IMockMultiToken multiToken;
    IERC20Forwarder forwarder;

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    function setUp() public override {
        super.setUp();
        vm.startPrank(deployer);
        forwarderFactory = new ERC20ForwarderFactory();
        bytes32 codeHash = keccak256(type(ERC20Forwarder).creationCode);
        multiToken = IMockMultiToken(
            address(new MockMultiToken(codeHash, address(forwarderFactory)))
        );

        forwarder = forwarderFactory.create(multiToken, 9);

        vm.stopPrank();
    }

    function testTransfer(uint256 AMOUNT) public {
        uint8 TOKEN_ID = 9;
        multiToken.mint(TOKEN_ID, alice, AMOUNT);

        assertEq(forwarder.balanceOf(alice), AMOUNT);

        vm.prank(alice);
        forwarder.transfer(bob, AMOUNT);

        assertEq(forwarder.balanceOf(alice), 0);
        assertEq(forwarder.balanceOf(bob), AMOUNT);
    }

    function testERC20ForwarderFactory() public {
        (IMultiToken token, uint256 tokenID) = forwarderFactory
            .getDeployDetails();
        assertEq(address(token), address((IMultiToken(address(1)))));
        assertEq(tokenID, 1);

        forwarder = forwarderFactory.create(multiToken, 5);

        // Transient variable should be reset after each create
        (token, tokenID) = forwarderFactory.getDeployDetails();
        assertEq(address(token), address((IMultiToken(address(1)))));
        assertEq(tokenID, 1);

        address retrievedForwarder = forwarderFactory.getForwarder(
            multiToken,
            5
        );

        assertEq(address(forwarder), retrievedForwarder);
    }

    // Test Forwarder contract
    function testForwarderMetadata() public {
        // Create a real tokenId.
        MockAssetId assetId = new MockAssetId();
        uint256 maturityTime = 126144000;
        uint256 id = assetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );

        // Create a forwarder.
        forwarder = forwarderFactory.create(multiToken, id);
        assertEq(forwarder.decimals(), 18);

        // Generate expected token name and symbol.
        string memory expectedName = "Hyperdrive Long: 126144000";
        string memory expectedSymbol = "HYPERDRIVE-LONG:126144000";

        // Test that the name and symbol are correct.
        assertEq(forwarder.name(), expectedName);
        assertEq(forwarder.symbol(), expectedSymbol);
    }

    function testForwarderERC20() public {
        uint256 AMOUNT = 10000 ether;
        uint256 TOKEN_ID = 8;
        forwarder = forwarderFactory.create(multiToken, TOKEN_ID);

        multiToken.mint(TOKEN_ID, alice, AMOUNT);

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

    function testNegativePermitBadNonce() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    forwarder.domainSeparator(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            1,
                            block.timestamp
                        )
                    )
                )
            )
        );

        vm.expectRevert();
        forwarder.permit(
            owner,
            address(0xCAFE),
            1e18,
            block.timestamp,
            v,
            r,
            s
        );
    }

    function testNegativePermitBadDeadline() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    forwarder.domainSeparator(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        vm.expectRevert();
        forwarder.permit(
            owner,
            address(0xCAFE),
            1e18,
            block.timestamp + 1,
            v,
            r,
            s
        );
    }

    function testNegativePermitPastDeadline() public {
        uint256 oldTimestamp = block.timestamp;
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    forwarder.domainSeparator(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            0,
                            oldTimestamp
                        )
                    )
                )
            )
        );

        vm.warp(block.timestamp + 1);

        vm.expectRevert();
        forwarder.permit(owner, address(0xCAFE), 1e18, oldTimestamp, v, r, s);
    }

    function testFailPermitReplay() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    forwarder.domainSeparator(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        forwarder.permit(
            owner,
            address(0xCAFE),
            1e18,
            block.timestamp,
            v,
            r,
            s
        );

        forwarder.permit(
            owner,
            address(0xCAFE),
            1e18,
            block.timestamp,
            v,
            r,
            s
        );
    }

    function testCanPermit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 nonce = forwarder.nonces(owner);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    forwarder.domainSeparator(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            nonce,
                            block.timestamp + 1000
                        )
                    )
                )
            )
        );

        forwarder.permit(
            owner,
            address(0xCAFE),
            1e18,
            block.timestamp + 1000,
            v,
            r,
            s
        );

        assertEq(forwarder.allowance(owner, address(0xCAFE)), 1e18);
        assertEq(forwarder.nonces(owner), nonce + 1);
    }

    function testCannotPermitTheZeroAddress() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 nonce = forwarder.nonces(owner);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    forwarder.domainSeparator(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            address(0),
                            address(0xCAFE),
                            1e18,
                            nonce,
                            block.timestamp + 1000
                        )
                    )
                )
            )
        );

        vm.expectRevert();
        forwarder.permit(
            address(0),
            address(0xCAFE),
            1e18,
            block.timestamp + 1000,
            v,
            r,
            s
        );

        assertEq(forwarder.allowance(address(0), address(0xCAFE)), 0);
        assertEq(forwarder.nonces(address(0)), nonce);
    }

    function testCannotSubmitAnInvalidSignature() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 nonce = forwarder.nonces(owner);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    forwarder.domainSeparator(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            nonce,
                            block.timestamp
                        )
                    )
                )
            )
        );

        vm.expectRevert();
        forwarder.permit(
            owner,
            address(0xCAFE),
            1e18,
            block.timestamp + 1000,
            v,
            r,
            s
        );

        assertEq(forwarder.allowance(owner, address(0xCAFE)), 0);
        assertEq(forwarder.nonces(owner), nonce);
    }

    function testAllowanceOfForwarder() public {
        bytes32 MULTITOKEN_PERMIT_TYPEHASH = keccak256(
            "PermitForAll(address owner,address spender,bool _approved,uint256 nonce,uint256 deadline)"
        );

        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        vm.prank(owner);
        forwarder.approve(address(0xCAFE), 100 ether);

        assertEq(forwarder.allowance(owner, address(0xCAFE)), 100 ether);

        uint256 deadline = block.timestamp + 1000;

        uint256 nonce = multiToken.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                multiToken.domainSeparator(),
                keccak256(
                    abi.encode(
                        MULTITOKEN_PERMIT_TYPEHASH,
                        owner,
                        address(0xCAFE),
                        true,
                        nonce,
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, structHash);

        multiToken.permitForAll(
            owner,
            address(0xCAFE),
            true,
            deadline,
            v,
            r,
            s
        );

        assertEq(
            forwarder.allowance(owner, address(0xCAFE)),
            type(uint256).max
        );
    }
}
