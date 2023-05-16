// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { MockAssetId } from "../../mocks/MockAssetId.sol";

contract AssetIdTest is HyperdriveTest {
    function test__constants() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockAssetId assetId = new MockAssetId();

        // Verify that the LP Asset ID constant is correct.
        assertEq(
            AssetId._LP_ASSET_ID,
            assetId.encodeAssetId(AssetId.AssetIdPrefix.LP, 0)
        );

        // Verify that the WithdrawalShare Asset ID constant is correct.
        assertEq(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID,
            assetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
        );
    }

    function test__encodeAssetIdInvalidTimestamp() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockAssetId assetId = new MockAssetId();
        uint256 maturityTime = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff +
                1;
        vm.expectRevert(Errors.InvalidTimestamp.selector);
        assetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime);
    }

    function test__encodeAssetIdLong() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockAssetId assetId = new MockAssetId();

        // Test Long Asset ID
        // block.timestamp + POSITION_DURATION = 94608000 + 31536000 = 126144000
        uint256 maturityTime = block.timestamp + POSITION_DURATION;
        // id = Long << 248 | 126144000 = 126144000
        uint256 expected = (1 << 248) | maturityTime;
        uint256 id = assetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );
        assertEq(id, expected);

        // Test Short Asset ID
        // id = Short << 248 | 126144000 = 126144000
        expected = (2 << 248) | maturityTime;
        id = assetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime);
        assertEq(id, expected);

        // Test WithdrawalShare Asset ID
        // id = WithdrawalShare << 248 | 126144000 = 126144000
        expected = (3 << 248) | maturityTime;
        id = assetId.encodeAssetId(
            AssetId.AssetIdPrefix.WithdrawalShare,
            maturityTime
        );
        assertEq(id, expected);
    }

    function test__decodeAssetId() external {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockAssetId assetId = new MockAssetId();

        // Test Long Asset ID
        uint256 maturityTime = 126144000;
        uint256 id = assetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );
        (AssetId.AssetIdPrefix prefix, uint256 timestamp) = assetId
            .decodeAssetId(id);
        assertEq(uint256(prefix), 1);
        assertEq(timestamp, maturityTime);

        // Test Short Asset ID
        id = assetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime);
        (prefix, timestamp) = assetId.decodeAssetId(id);
        assertEq(uint256(prefix), 2);
        assertEq(timestamp, maturityTime);

        // Test WithdrawShare Asset ID
        id = assetId.encodeAssetId(
            AssetId.AssetIdPrefix.WithdrawalShare,
            maturityTime
        );
        (prefix, timestamp) = assetId.decodeAssetId(id);
        assertEq(uint256(prefix), 3);
        assertEq(timestamp, maturityTime);
    }
}
