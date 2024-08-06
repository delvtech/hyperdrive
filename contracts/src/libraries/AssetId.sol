// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

/// @author DELV
/// @title Hyperdrive
/// @notice A library that handles the encoding and decoding of asset IDs for
///         Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library AssetId {
    uint256 internal constant _LP_ASSET_ID = 0;
    uint256 internal constant _WITHDRAWAL_SHARE_ASSET_ID =
        uint256(AssetIdPrefix.WithdrawalShare) << 248;

    enum AssetIdPrefix {
        LP,
        Long,
        Short,
        WithdrawalShare
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
            revert IHyperdrive.InvalidTimestamp();
        }
        assembly ("memory-safe") {
            id := or(shl(0xf8, _prefix), _timestamp)
        }
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
        assembly ("memory-safe") {
            _prefix := shr(0xf8, _id) // shr 248 bits
            _timestamp := and(
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
                _id
            ) // 248 bit-mask
        }
    }

    /// @dev Converts an asset ID to a token name.
    /// @param _id The asset ID.
    /// @return _name The token name.
    function assetIdToName(
        uint256 _id
    ) internal pure returns (string memory _name) {
        (AssetIdPrefix prefix, uint256 timestamp) = decodeAssetId(_id);
        string memory _timestamp = toString(timestamp);
        if (prefix == AssetIdPrefix.LP) {
            _name = "Hyperdrive LP";
        } else if (prefix == AssetIdPrefix.Long) {
            _name = string(abi.encodePacked("Hyperdrive Long: ", _timestamp));
        } else if (prefix == AssetIdPrefix.Short) {
            _name = string(abi.encodePacked("Hyperdrive Short: ", _timestamp));
        } else if (prefix == AssetIdPrefix.WithdrawalShare) {
            _name = "Hyperdrive Withdrawal Share";
        }
    }

    /// @dev Converts an asset ID to a token symbol.
    /// @param _id The asset ID.
    /// @return _symbol The token symbol.
    function assetIdToSymbol(
        uint256 _id
    ) internal pure returns (string memory _symbol) {
        (AssetIdPrefix prefix, uint256 timestamp) = decodeAssetId(_id);
        string memory _timestamp = toString(timestamp);
        if (prefix == AssetIdPrefix.LP) {
            _symbol = "HYPERDRIVE-LP";
        } else if (prefix == AssetIdPrefix.Long) {
            _symbol = string(abi.encodePacked("HYPERDRIVE-LONG:", _timestamp));
        } else if (prefix == AssetIdPrefix.Short) {
            _symbol = string(abi.encodePacked("HYPERDRIVE-SHORT:", _timestamp));
        } else if (prefix == AssetIdPrefix.WithdrawalShare) {
            _symbol = "HYPERDRIVE-WS";
        }
    }

    /// @dev Converts an unsigned integer to a string.
    /// @param _num The integer to be converted.
    /// @return result The stringified integer.
    function toString(
        uint256 _num
    ) internal pure returns (string memory result) {
        // We overallocate memory for the string. The maximum number of digits
        // that a uint256 can hold is log_10(2 ^ 256) which is approximately
        // 77.06. We round up so that we have space for the last digit.
        uint256 maxStringLength = 78;
        bytes memory rawResult = new bytes(maxStringLength);

        // Loop through the integer and add each digit to the raw result,
        // starting at the end of the string and working towards the beginning.
        uint256 digits = 0;
        for (; _num != 0; _num /= 10) {
            rawResult[maxStringLength - digits - 1] = bytes1(
                uint8((_num % 10) + 48)
            );
            digits++;
        }

        // Point the string result to the beginning of the stringified integer
        // and update the length.
        assembly {
            result := add(rawResult, sub(maxStringLength, digits))
            mstore(result, digits)
        }
        return result;
    }
}
