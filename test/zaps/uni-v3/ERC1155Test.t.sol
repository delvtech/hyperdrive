// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { console2 as console } from "forge-std/console2.sol";

import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { UniV3ZapTest } from "./UniV3Zap.t.sol";

contract ERC1155Test is UniV3ZapTest {
    /// @dev Ensure that the zap contract can't receive direct transfers of
    ///      ERC1155 tokens.
    function test_zap_cannot_receive_direct_transfer() external {
        // Alice opens a long.
        vm.stopPrank();
        vm.startPrank(alice);
        IERC20(DAI).approve(address(SDAI_HYPERDRIVE), 100_000e18);
        (uint256 maturityTime, uint256 bondAmount) = SDAI_HYPERDRIVE.openLong(
            100_000e18,
            0,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: ""
            })
        );

        // Alice attempts to transfer her long to the UniV3Zap contract. This
        // should fail.
        vm.expectRevert(IHyperdrive.ERC1155InvalidReceiver.selector);
        SDAI_HYPERDRIVE.safeTransferFrom(
            alice,
            address(zap),
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bondAmount,
            ""
        );
    }

    /// @dev Ensure that the zap contract can't receive direct batch transfers
    ///      of ERC1155 tokens.
    function test_zap_cannot_receive_direct_batch_transfer() external {
        // Alice opens a long.
        vm.stopPrank();
        vm.startPrank(alice);
        IERC20(DAI).approve(address(SDAI_HYPERDRIVE), 100_000e18);
        (uint256 maturityTime, uint256 bondAmount) = SDAI_HYPERDRIVE.openLong(
            100_000e18,
            0,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: ""
            })
        );

        // Alice attempts to transfer her long to the UniV3Zap contract. This
        // should fail.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(IHyperdrive.ERC1155InvalidReceiver.selector);
        uint256[] memory ids = new uint256[](1);
        ids[0] = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = bondAmount;
        SDAI_HYPERDRIVE.safeBatchTransferFrom(
            alice,
            address(zap),
            ids,
            amounts,
            ""
        );
    }
}
