// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import { IHyperdrive } from "../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../contracts/src/interfaces/IHyperdriveAdminController.sol";
import { IERC20 } from "../../contracts/src/interfaces/IERC20.sol";
import { ERC20Mintable } from "../../contracts/test/ERC20Mintable.sol";
import { AssetId } from "../../contracts/src/libraries/AssetId.sol";
import { ERC20ForwarderFactory } from "../../contracts/src/token/ERC20ForwarderFactory.sol";
import { MockAssetId } from "../../contracts/test/MockAssetId.sol";
import { HyperdriveMultiToken } from "../../contracts/src/internal/HyperdriveMultiToken.sol";
import { MockHyperdrive } from "../../contracts/test/MockHyperdrive.sol";
import { IMockHyperdrive, MockHyperdrive } from "../../contracts/test/MockHyperdrive.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { Lib } from "../utils/Lib.sol";

// Helper contracts for testing receiver functionality
contract NonReceiverContract {}

contract ReceiverContract is IERC1155Receiver {
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

contract DummyHyperdriveMultiToken is HyperdriveMultiToken, MockHyperdrive {
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) MockHyperdrive(_config, IHyperdriveAdminController(address(0))) {}

    function callOnlyLinker(
        uint256 tokenId
    ) external view onlyLinker(tokenId) returns (address) {
        return address(0);
    }
}

contract MultiTokenTest is HyperdriveTest {
    using Lib for *;

    function testFactory() public view {
        assertEq(
            hyperdrive.getPoolConfig().linkerFactory,
            address(forwarderFactory)
        );
    }

    function testLinkerCodeHash() public view {
        assertEq(
            hyperdrive.getPoolConfig().linkerCodeHash,
            forwarderFactory.ERC20LINK_HASH()
        );
    }

    function test__metadata() public {
        // Create a real tokenId.
        MockAssetId assetId = new MockAssetId();
        uint256 maturityTime = 126144000;
        uint256 id = assetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );

        // Generate expected token name and symbol.
        string memory expectedName = "Hyperdrive Long: 126144000";
        string memory expectedSymbol = "HYPERDRIVE-LONG:126144000";

        // Test that the name and symbol are correct.
        assertEq(hyperdrive.name(id), expectedName);
        assertEq(hyperdrive.symbol(id), expectedSymbol);
    }

    function testOnlyLinkerInvalidERC20Bridge() public {
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.baseToken = IERC20(address(baseToken));
        config.minimumShareReserves = 1e15;
        DummyHyperdriveMultiToken multitoken = new DummyHyperdriveMultiToken(
            config
        );
        vm.expectRevert(IHyperdrive.InvalidERC20Bridge.selector);
        multitoken.callOnlyLinker(1);
    }

    function testPermitForAll() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 deadline = block.timestamp + 1000;

        uint256 nonce = hyperdrive.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                hyperdrive.domainSeparator(),
                keccak256(
                    abi.encode(
                        hyperdrive.PERMIT_TYPEHASH(),
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

        hyperdrive.permitForAll(
            owner,
            address(0xCAFE),
            true,
            deadline,
            v,
            r,
            s
        );

        assertEq(hyperdrive.isApprovedForAll(owner, address(0xCAFE)), true);

        // Check that nonce increments
        assertEq(hyperdrive.nonces(owner), nonce + 1);
    }

    function testPermitForAllZeroOwner() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 deadline = block.timestamp + 1000;

        uint256 nonce = hyperdrive.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                hyperdrive.domainSeparator(),
                keccak256(
                    abi.encode(
                        hyperdrive.PERMIT_TYPEHASH(),
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
        hyperdrive.permitForAll(
            address(0),
            address(0xCAFE),
            true,
            deadline,
            v,
            r,
            s
        );

        assertEq(hyperdrive.isApprovedForAll(owner, address(0xCAFE)), false);
    }

    function testNegativePermitBadNonce() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 deadline = block.timestamp + 1000;

        uint256 nonce = hyperdrive.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                hyperdrive.domainSeparator(),
                keccak256(
                    abi.encode(
                        hyperdrive.PERMIT_TYPEHASH(),
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
        hyperdrive.permitForAll(
            owner,
            address(0xCAFE),
            true,
            deadline,
            v,
            r,
            s
        );

        assertEq(hyperdrive.isApprovedForAll(owner, address(0xCAFE)), false);
    }

    function testNegativePermitExpired() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 deadline = block.timestamp - 1;

        uint256 nonce = hyperdrive.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                hyperdrive.domainSeparator(),
                keccak256(
                    abi.encode(
                        hyperdrive.PERMIT_TYPEHASH(),
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
        hyperdrive.permitForAll(
            owner,
            address(0xCAFE),
            true,
            deadline,
            v,
            r,
            s
        );

        assertEq(hyperdrive.isApprovedForAll(owner, address(0xCAFE)), false);
    }

    function testNegativePermitBadSignature() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 deadline = block.timestamp + 1000;

        uint256 nonce = hyperdrive.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                hyperdrive.domainSeparator(),
                keccak256(
                    abi.encode(
                        hyperdrive.PERMIT_TYPEHASH(),
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
        hyperdrive.permitForAll(
            owner,
            address(0xF00DBABE),
            true,
            deadline,
            v,
            r,
            s
        );

        assertEq(
            hyperdrive.isApprovedForAll(owner, address(0xF00DBABE)),
            false
        );
    }

    function testCannotTransferZeroAddrSafeTransferFrom() public {
        vm.expectRevert();
        hyperdrive.safeTransferFrom(alice, address(0), 0, 10e18, "");

        vm.expectRevert();
        hyperdrive.safeTransferFrom(address(0), alice, 0, 10e18, "");
    }

    function testSafeTransferFrom() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 deadline = block.timestamp + 1000;

        uint256 nonce = hyperdrive.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                hyperdrive.domainSeparator(),
                keccak256(
                    abi.encode(
                        hyperdrive.PERMIT_TYPEHASH(),
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

        hyperdrive.permitForAll(
            owner,
            address(0xCAFE),
            true,
            deadline,
            v,
            r,
            s
        );
        IMockHyperdrive(address(hyperdrive)).mint(1, owner, 100 ether);

        vm.startPrank(address(0xCAFE));
        hyperdrive.safeTransferFrom(owner, bob, 1, 100 ether, "");
    }

    function testSafeTransferFromToNonReceiverContractReverts() public {
        NonReceiverContract nonReceiver = new NonReceiverContract();
        address owner = alice;

        IMockHyperdrive(address(hyperdrive)).mint(1, owner, 100 ether);

        vm.startPrank(owner);
        hyperdrive.setApprovalForAll(address(this), true);

        // Expect revert when transferring to non-receiver contract
        vm.expectRevert(IHyperdrive.ERC1155InvalidReceiver.selector);
        hyperdrive.safeTransferFrom(
            owner,
            address(nonReceiver),
            1,
            100 ether,
            ""
        );
    }

    function testSafeTransferFromToEOA() public {
        address owner = alice;
        IMockHyperdrive(address(hyperdrive)).mint(1, owner, 100 ether);

        vm.startPrank(owner);
        hyperdrive.setApprovalForAll(address(this), true);

        hyperdrive.safeTransferFrom(owner, bob, 1, 100 ether, "");

        // Verify balance update
        assertEq(hyperdrive.balanceOf(1, bob), 100 ether);
    }

    function testSafeTransferFromToReceiverContractSucceeds() public {
        ReceiverContract receiver = new ReceiverContract();
        address owner = alice;

        IMockHyperdrive(address(hyperdrive)).mint(1, owner, 100 ether);

        vm.startPrank(owner);
        hyperdrive.setApprovalForAll(address(this), true);

        hyperdrive.safeTransferFrom(owner, address(receiver), 1, 100 ether, "");

        // Verify balance update
        assertEq(hyperdrive.balanceOf(1, address(receiver)), 100 ether);
    }

    function testCannotTransferZeroAddrSafeBatchTransferFrom() public {
        vm.expectRevert();
        hyperdrive.safeBatchTransferFrom(
            alice,
            address(0),
            new uint256[](0),
            new uint256[](0),
            ""
        );

        vm.expectRevert();
        hyperdrive.safeBatchTransferFrom(
            address(0),
            alice,
            new uint256[](0),
            new uint256[](0),
            ""
        );
    }

    function testCannotSendInconsistentLengths() public {
        vm.expectRevert();
        hyperdrive.safeBatchTransferFrom(
            alice,
            bob,
            new uint256[](0),
            new uint256[](1),
            ""
        );

        vm.expectRevert();
        hyperdrive.safeBatchTransferFrom(
            alice,
            bob,
            new uint256[](1),
            new uint256[](0),
            ""
        );
    }

    function testSafeBatchTransferFrom() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        uint256 deadline = block.timestamp + 1000;

        uint256 nonce = hyperdrive.nonces(owner);

        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                hyperdrive.domainSeparator(),
                keccak256(
                    abi.encode(
                        hyperdrive.PERMIT_TYPEHASH(),
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

        hyperdrive.permitForAll(
            owner,
            address(0xCAFE),
            true,
            deadline,
            v,
            r,
            s
        );

        IMockHyperdrive(address(hyperdrive)).mint(1, owner, 100 ether);
        IMockHyperdrive(address(hyperdrive)).mint(2, owner, 50 ether);
        IMockHyperdrive(address(hyperdrive)).mint(3, owner, 10 ether);

        uint256[] memory ids = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 50 ether;
        amounts[2] = 10 ether;

        vm.startPrank(address(0xCAFE));
        hyperdrive.safeBatchTransferFrom(owner, bob, ids, amounts, "");
    }

    function testSafeBatchTransferFromFailsWithoutApproval() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        IMockHyperdrive(address(hyperdrive)).mint(1, owner, 100 ether);
        IMockHyperdrive(address(hyperdrive)).mint(2, owner, 50 ether);
        IMockHyperdrive(address(hyperdrive)).mint(3, owner, 10 ether);

        uint256[] memory ids = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 50 ether;
        amounts[2] = 10 ether;

        vm.expectRevert();
        hyperdrive.safeBatchTransferFrom(owner, bob, ids, amounts, "");
    }

    function testSafeBatchTransferFromToEOA() public {
        address owner = alice;
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        IMockHyperdrive(address(hyperdrive)).mint(1, owner, 100 ether);

        vm.startPrank(owner);
        hyperdrive.setApprovalForAll(address(this), true);

        hyperdrive.safeBatchTransferFrom(owner, bob, ids, amounts, "");

        // Verify balances
        assertEq(hyperdrive.balanceOf(1, bob), 100 ether);
    }

    function testSafeBatchTransferFromToNonReceiverContractReverts() public {
        NonReceiverContract nonReceiver = new NonReceiverContract();
        address owner = alice;
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        IMockHyperdrive(address(hyperdrive)).mint(1, owner, 100 ether);

        vm.startPrank(owner);
        hyperdrive.setApprovalForAll(address(this), true);

        // Expect revert when transferring to non-receiver contract
        vm.expectRevert(IHyperdrive.ERC1155InvalidReceiver.selector);
        hyperdrive.safeBatchTransferFrom(
            owner,
            address(nonReceiver),
            ids,
            amounts,
            ""
        );
    }

    function testSafeBatchTransferFromToReceiverContractSucceeds() public {
        ReceiverContract receiver = new ReceiverContract();
        address owner = alice;
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        IMockHyperdrive(address(hyperdrive)).mint(1, owner, 100 ether);

        vm.startPrank(owner);
        hyperdrive.setApprovalForAll(address(this), true);

        hyperdrive.safeBatchTransferFrom(
            owner,
            address(receiver),
            ids,
            amounts,
            ""
        );

        // Verify balance update
        assertEq(hyperdrive.balanceOf(1, address(receiver)), 100 ether);
    }
}
