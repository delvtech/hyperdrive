// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";

/// @author Delve
/// @title Hyperdrive
/// @notice A library that handles the encoding and decoding of asset IDs for
///         Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library AssetId {
    uint256 internal constant _LP_ASSET_ID = 0;

    // TODO: We'll ultimately want to use the upper range of `uint8` so
    // constants may be more appropriate. This would give the extraData more
    // range.
    enum AssetIdPrefix {
        Long,
        Short,
        LongWithdrawalShare,
        ShortWithdrawalShare
    }

    /// @dev Encodes a prefix and a timestamp into an asset ID. Asset IDs are
    ///      used so that LP, long, and short tokens can all be represented in a
    ///      single MultiToken instance. The zero asset ID indicates the LP
    ///      token.
    /// @param _prefix A one byte prefix that specifies the asset type.
    /// @param _timestamp A timestamp associated with the asset.
    /// @return id The asset ID.
    function encodeAssetId(
        AssetIdPrefix _prefix,
        uint256 _timestamp
    ) internal pure returns (uint256 id) {
        // [identifier: 8 bits][timestamp: 248 bits]
        if (
            _timestamp >
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        ) {
            revert Errors.InvalidTimestamp();
        }
        assembly {
            id := or(shl(0xf8, _prefix), _timestamp)
        }
        return id;
    }

    /// @dev Decodes an encoded asset ID into it's constituent parts of an
    ///      identifier, data and a timestamp.
    /// @param _id The asset ID.
    /// @return _prefix A one byte prefix that specifies the asset type.
    /// @return _timestamp A timestamp associated with the asset.
    function decodeAssetId(
        uint256 _id
    ) internal pure returns (AssetIdPrefix _prefix, uint256 _timestamp) {
        // [identifier: 8 bits][timestamp: 248 bits]
        assembly {
            _prefix := shr(0xf8, _id) // shr 248 bits
            _timestamp := and(
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
                _id
            ) // 248 bit-mask
        }
    }
}
