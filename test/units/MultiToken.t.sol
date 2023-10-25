// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { MultiTokenDataProvider } from "contracts/src/token/MultiTokenDataProvider.sol";
import { MockAssetId } from "../mocks/MockAssetId.sol";
import { MockMultiToken, IMockMultiToken } from "contracts/test/MockMultiToken.sol";
import { BaseTest } from "test/utils/BaseTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract MultiTokenTest is BaseTest {
    using Lib for *;
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

    function testFactory() public {
        assertEq(multiToken.factory(), address(forwarderFactory));
    }

    // TODO - really needs a better test
    function testLinkerCodeHash() public {
        assertEq(multiToken.linkerCodeHash(), bytes32(0));
    }

    function test__metadata() public {
        // Create a real tokenId.
        MockAssetId assetId = new MockAssetId();
        uint256 maturityTime = block.timestamp + 365 days;
        uint256 id = assetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );

        // Generate expected token name and symbol.
        (, uint256 timestamp) = assetId.decodeAssetId(id);
        string memory _timestamp = int256(timestamp).toString(0);
        string memory expectedName = string.concat(
            "Hyperdrive Long: ",
            _timestamp
        );
        string memory expectedSymbol = string.concat(
            "HYPERDRIVE-LONG:",
            _timestamp
        );
        vm.startPrank(alice);
        multiToken.__setNameAndSymbol(id, expectedName, expectedSymbol);
        vm.stopPrank();

        // Test that the name and symbol are correct.
        assertEq(multiToken.name(id), expectedName);
        assertEq(multiToken.symbol(id), expectedSymbol);
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

    function testCannotTransferZeroAddrBatchTransferFrom() public {
        vm.expectRevert();
        multiToken.batchTransferFrom(
            alice,
            address(0),
            new uint256[](0),
            new uint256[](0)
        );

        vm.expectRevert();
        multiToken.batchTransferFrom(
            address(0),
            alice,
            new uint256[](0),
            new uint256[](0)
        );
    }

    function testCannotSendInconsistentLengths() public {
        vm.expectRevert();
        multiToken.batchTransferFrom(
            alice,
            bob,
            new uint256[](0),
            new uint256[](1)
        );

        vm.expectRevert();
        multiToken.batchTransferFrom(
            alice,
            bob,
            new uint256[](1),
            new uint256[](0)
        );
    }

    function testBatchTransferFrom() public {
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

        multiToken.mint(1, owner, 100 ether);
        multiToken.mint(2, owner, 50 ether);
        multiToken.mint(3, owner, 10 ether);

        uint256[] memory ids = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 50 ether;
        amounts[2] = 10 ether;

        vm.prank(address(0xCAFE));
        multiToken.batchTransferFrom(owner, bob, ids, amounts);
    }

    function testBatchTransferFromFailsWithoutApproval() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        multiToken.mint(1, owner, 100 ether);
        multiToken.mint(2, owner, 50 ether);
        multiToken.mint(3, owner, 10 ether);

        uint256[] memory ids = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 50 ether;
        amounts[2] = 10 ether;

        vm.expectRevert();
        multiToken.batchTransferFrom(owner, bob, ids, amounts);
    }
}
