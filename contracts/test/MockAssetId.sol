// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { AssetId } from "../src/libraries/AssetId.sol";

contract MockAssetId {
    function encodeAssetId(
        AssetId.AssetIdPrefix _prefix,
        uint256 _timestamp
    ) external pure returns (uint256) {
        uint256 id = AssetId.encodeAssetId(_prefix, _timestamp);
        return id;
    }

    function decodeAssetId(
        uint256 _id
    ) external pure returns (AssetId.AssetIdPrefix, uint256) {
        (AssetId.AssetIdPrefix prefix, uint256 timestamp) = AssetId
            .decodeAssetId(_id);
        return (prefix, timestamp);
    }

    function assetIdToName(uint256 _id) external pure returns (string memory) {
        string memory _name = AssetId.assetIdToName(_id);
        return _name;
    }

    function assetIdToSymbol(
        uint256 _id
    ) external pure returns (string memory) {
        string memory _symbol = AssetId.assetIdToSymbol(_id);
        return _symbol;
    }
}
