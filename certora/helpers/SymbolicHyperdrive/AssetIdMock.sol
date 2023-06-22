/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";

contract AssetIdMock {

    enum AssetIdPrefix {
        LP,
        Long,
        Short,
        WithdrawalShare
    }

    function encodeAssetId(
        AssetId.AssetIdPrefix _prefix,
        uint256 _timestamp
    ) external pure returns (uint256) {
        return AssetId.encodeAssetId(_prefix, _timestamp);
    }
}
