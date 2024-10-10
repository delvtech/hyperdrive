// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/// @title Path
/// @author DELV
/// @notice This is a library for interacting with Uniswap's multi-hop paths.
library UniV3Path {
    /// @dev Returns the input token of a Uniswap swap.
    /// @param _path The Uniswap path for a multi-hop fill.
    /// @return tokenIn_ The input token of a Uniswap swap.
    function tokenIn(
        bytes memory _path
    ) internal pure returns (address tokenIn_) {
        // Look up the `tokenIn` as the first part of the path.
        assembly {
            tokenIn_ := div(
                mload(add(add(_path, 0x20), 0x0)),
                0x1000000000000000000000000
            )
        }

        return tokenIn_;
    }

    /// @dev Returns the output token of a Uniswap swap.
    /// @param _path The Uniswap path for a multi-hop fill.
    /// @return tokenOut_ The output token of a Uniswap swap.
    function tokenOut(
        bytes memory _path
    ) internal pure returns (address tokenOut_) {
        // Look up the `tokenOut` as the last address in the path.
        assembly {
            tokenOut_ := div(
                // NOTE: We add the path pointer to the path length plus 12
                // because this will point us 20 bytes from the end of the path.
                // This gives us the last address in the path.
                mload(add(add(_path, mload(_path)), 12)),
                0x1000000000000000000000000
            )
        }

        return tokenOut_;
    }
}
