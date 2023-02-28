// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import "contracts/test/MockAssetId.sol";
import "forge-std/console2.sol";

contract AssetIdTest is HyperdriveTest {
    function test__encodeAssetIdInvalidTimestamp() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockAssetId assetId = new MockAssetId();
        uint256 maturityTime = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff +
                1;
        vm.expectRevert(Errors.InvalidTimestamp.selector);
        assetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime);
    }

    function test__encodeAssetIdLong() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockAssetId assetId = new MockAssetId();

        // Test Long Asset ID
        // block.timestamp + POSITION_DURATION = 94608000 + 31536000 = 126144000
        uint256 maturityTime = block.timestamp + POSITION_DURATION;
        // id = Long << 248 | 126144000 = 126144000
        uint256 expected = (0 << 248) | maturityTime;
        uint256 id = assetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );
        assertEq(id, expected);
        console2.log("long id: ", id);

        // Test Short Asset ID
        // id = Short << 248 | 126144000 = 126144000
        expected = (1 << 248) | maturityTime;
        id = assetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime);
        assertEq(id, expected);
        console2.log("short id: ", id);

        // Test LongWithdrawalShare Asset ID
        // id = LongWithdrawalShare << 248 | 126144000 = 126144000
        expected = (2 << 248) | maturityTime;
        id = assetId.encodeAssetId(
            AssetId.AssetIdPrefix.LongWithdrawalShare,
            maturityTime
        );
        assertEq(id, expected);
        console2.log("long withdrawal id: ", id);

        // Test ShortWithdrawalShare Asset ID
        // id = ShortWithdrawalShare << 248 | 126144000 = 126144000
        expected = (3 << 248) | maturityTime;
        id = assetId.encodeAssetId(
            AssetId.AssetIdPrefix.ShortWithdrawalShare,
            maturityTime
        );
        assertEq(id, expected);
        console2.log("short withdrawal id: ", id);
    }

    function test__decodeAssetId() public {
        // NOTE: Coverage only works if I initialize the fixture in the test function
        MockAssetId assetId = new MockAssetId();

        // Test Long Asset ID
        uint256 maturityTime = 126144000;
        uint256 id = maturityTime;
        (AssetId.AssetIdPrefix prefix, uint256 timestamp) = assetId
            .decodeAssetId(id);
        assertEq(uint256(prefix), 0);
        assertEq(timestamp, maturityTime);

        // Test Short Asset ID
        id = 452312848583266388373324160190187140051835877600158453279131187531036806656;
        (prefix, timestamp) = assetId.decodeAssetId(id);
        assertEq(uint256(prefix), 1);
        assertEq(timestamp, maturityTime);

        // Test LongWithdrawalShare Asset ID
        id = 904625697166532776746648320380374280103671755200316906558262375061947469312;
        (prefix, timestamp) = assetId.decodeAssetId(id);
        assertEq(uint256(prefix), 2);
        assertEq(timestamp, maturityTime);

        // Test ShortWithdrawalShare Asset ID
        id = 1356938545749799165119972480570561420155507632800475359837393562592858131968;
        (prefix, timestamp) = assetId.decodeAssetId(id);
        assertEq(uint256(prefix), 3);
        assertEq(timestamp, maturityTime);
    }
}
