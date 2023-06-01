// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { ForwarderFactory } from "contracts/src/ForwarderFactory.sol";
import { MultiTokenDataProvider } from "contracts/src/MultiTokenDataProvider.sol";
import { MockMultiToken, IMockMultiToken } from "contracts/test/MockMultiToken.sol";
import { BaseTest } from "test/utils/BaseTest.sol";
import { console } from "forge-std/console.sol";

contract MultiTokenTest is BaseTest {
    IMockMultiToken multiToken;

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "PermitForAll(address owner,address spender,bool _approved,uint256 nonce,uint256 deadline)"
        );

    function setUp() public override {
        super.setUp();
        vm.startPrank(deployer);
        forwarderFactory = new ForwarderFactory();
        address dataProvider = address(
            new MultiTokenDataProvider(bytes32(0), address(forwarderFactory))
        );

        multiToken = IMockMultiToken(
            address(
                new MockMultiToken(
                    dataProvider,
                    bytes32(0),
                    address(forwarderFactory)
                )
            )
        );
        vm.stopPrank();
    }

    function test__name_symbol() public {
        vm.startPrank(alice);
        multiToken.__setNameAndSymbol(5, "Token", "TKN");
        vm.stopPrank();
        assertEq(multiToken.name(5), "Token");
        assertEq(multiToken.symbol(5), "TKN");
    }

    function testPermitForAll() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 deadline = block.timestamp + 1000;

        uint256 nonce = multiToken.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                multiToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
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

        assertEq(multiToken.isApprovedForAll(owner, address(0xCAFE)), true);

        // Check that nonce increments
        assertEq(multiToken.nonces(owner), nonce + 1);
    }

    function testNegativePermitBadNonce() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 deadline = block.timestamp + 1000;

        uint256 nonce = multiToken.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                multiToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        address(0xCAFE),
                        true,
                        nonce + 5,
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, structHash);

        vm.expectRevert();
        multiToken.permitForAll(
            owner,
            address(0xCAFE),
            true,
            deadline,
            v,
            r,
            s
        );

        assertEq(multiToken.isApprovedForAll(owner, address(0xCAFE)), false);
    }

    function testNegativePermitExpired() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 deadline = block.timestamp - 1;

        uint256 nonce = multiToken.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                multiToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        address(0xCAFE),
                        true,
                        nonce + 5,
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, structHash);

        vm.expectRevert();
        multiToken.permitForAll(
            owner,
            address(0xCAFE),
            true,
            deadline,
            v,
            r,
            s
        );

        assertEq(multiToken.isApprovedForAll(owner, address(0xCAFE)), false);
    }

    function testNegativePermitBadSignature() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 deadline = block.timestamp + 1000;

        uint256 nonce = multiToken.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                multiToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
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

        vm.expectRevert();
        multiToken.permitForAll(
            owner,
            address(0xF00DBABE),
            true,
            deadline,
            v,
            r,
            s
        );

        assertEq(
            multiToken.isApprovedForAll(owner, address(0xF00DBABE)),
            false
        );
    }
}
