methods {
    function encodeAssetId(MockAssetId.AssetIdPrefix, uint256) external returns (uint256) envfree;
    function decodeAssetId(uint256) external returns (MockAssetId.AssetIdPrefix, uint256) envfree;
}

/// Verified (and caught an injected bug of wrong bitshift)
rule encodeDecodeInverse(MockAssetId.AssetIdPrefix prefix, uint256 timestamp) {
    MockAssetId.AssetIdPrefix _prefix;
    uint256 _timestamp;

    uint256 id = encodeAssetId(prefix, timestamp);
    _prefix, _timestamp = decodeAssetId(id);

    assert prefix == _prefix;
    assert timestamp == _timestamp;
}
/// Verified (and caught an injected bug of wrong bitshift)
rule decodeEncodeInverse(uint256 id) {
    MockAssetId.AssetIdPrefix prefix;
    uint256 timestamp;
    prefix, timestamp = decodeAssetId(id);

    uint256 _id = encodeAssetId(prefix, timestamp);

    assert _id == id;
}
