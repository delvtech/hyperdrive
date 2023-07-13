methods {
    function encodeAssetId(AssetId.AssetIdPrefix, uint256) external returns (uint256) envfree;
    function decodeAssetId(uint256) external returns (AssetId.AssetIdPrefix, uint256) envfree;
}

/// Verified (and caught an injected bug of wrong bitshift)
/// encodeAssetId() -> decodeAssetId() should return the same _prefix and _timestamp as were encoded initially
rule encodeDecodeInverse(AssetId.AssetIdPrefix prefix, uint256 timestamp) {
    AssetId.AssetIdPrefix _prefix;
    uint256 _timestamp;

    uint256 id = encodeAssetId(prefix, timestamp);
    _prefix, _timestamp = decodeAssetId(id);

    assert prefix == _prefix;
    assert timestamp == _timestamp;
}

/// Verified (and caught an injected bug of wrong bitshift)
///decodeAssetId() ->  encodeAssetId() should return the same _id as were decoded initially
rule decodeEncodeInverse(uint256 id) {
    AssetId.AssetIdPrefix prefix;
    uint256 timestamp;
    prefix, timestamp = decodeAssetId(id);

    uint256 _id = encodeAssetId(prefix, timestamp);

    assert _id == id;
}
