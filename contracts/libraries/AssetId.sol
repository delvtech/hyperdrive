// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

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
        Short
    }

    /// @dev Encodes an identifier, data, and a timestamp into an asset ID.
    ///      Asset IDs are used so that LP, long, and short tokens can all be
    ///      represented in a single MultiToken instance. The zero asset ID
    ///      indicates the LP token.
    /// TODO: Update this comment when we make the range more restrictive.
    /// @param _prefix A one byte prefix that specifies the asset type.
    /// @param _data Data associated with the asset. This is an efficient way of
    ///        fingerprinting data as the user can supply this data, and the
    ///        token balance ensures that the data is associated with the asset.
    /// @param _timestamp A timestamp associated with the asset.
    /// @return id The asset ID.
    function encodeAssetId(
        AssetIdPrefix _prefix,
        uint256 _data,
        uint256 _timestamp
    ) internal pure returns (uint256 id) {
        // Ensure that _data is a 216 bit number.
        if (_data > 0xffffffffffffffffffffffffffffffffffffffffffffffffffffff) {
            revert Errors.AssetIDCorruption();
        }
        // [identifier: 8 bits][data: 216 bits][timestamp: 32 bits]
        assembly {
            id := or(
                or(shl(0xf8, _prefix), shl(0x20, _data)),
                mod(_timestamp, 0x20)
            )
        }
        return id;
    }

    /// @dev Decodes an asset ID into an identifier, extra data, and a timestamp.
    /// @param _id The asset ID.
    /// TODO: Update this comment when we make the range more restrictive.
    /// @return prefix A one byte prefix that specifies the asset type.
    /// @return data Data associated with the asset. This is an efficient way of
    ///        fingerprinting data as the user can supply this data, and the
    ///        token balance ensures that the data is associated with the asset.
    /// @return timestamp_ A timestamp associated with the asset.
    function decodeAssetId(
        uint256 _id
    )
        internal
        pure
        returns (AssetIdPrefix prefix, uint256 data, uint256 timestamp_)
    {
        // [identifier: 8 bits][data: 216 bits][timestamp: 32 bits]
        assembly {
            prefix := shr(0xf8, _id)
            data := and(
                shr(0x20, _id),
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffff
            )
            timestamp_ := and(shr(0x20, _id), 0xffffffff)
        }
        // In the case of shorts, extra data is the share price at which the
        // short was opened. Hyperdrive assumes that the yield source accrues
        // non-negative interest, so an opening share price less than the fixed
        // point multiplicative identity indicates corruption. In the case of
        // longs, the extra data is unused.
        if (
            (prefix == AssetIdPrefix.Long && data > 0) ||
            (prefix == AssetIdPrefix.Short && data < FixedPointMath.ONE_18)
        ) {
            revert Errors.AssetIDCorruption();
        }
        return (prefix, data, timestamp_);
    }
}
