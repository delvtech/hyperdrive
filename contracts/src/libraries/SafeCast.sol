/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

/// @notice Safe unsigned integer casting library that reverts on overflow.
/// @author Inspired by Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/SafeCastLib.sol)
/// @author Inspired by OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeCast.sol)
library SafeCast {
    /// @notice This function safely casts a uint256 to a uint112.
    /// @param x The uint256 to cast to uint112.
    /// @return y The uint112 casted from x.
    function toUint112(uint256 x) internal pure returns (uint112 y) {
        if (x > type(uint112).max) {
            revert IHyperdrive.UnsafeCastToUint112();
        }
        y = uint112(x);
    }

    /// @notice This function safely casts a uint256 to a uint128.
    /// @param x The uint256 to cast to uint128.
    /// @return y The uint128 casted from x.
    function toUint128(uint256 x) internal pure returns (uint128 y) {
        if (x > type(uint128).max) {
            revert IHyperdrive.UnsafeCastToUint128();
        }
        y = uint128(x);
    }

    /// @notice This function safely casts an int256 to an int128.
    /// @param x The int256 to cast to int128.
    /// @return y The int128 casted from x.
    function toInt128(int256 x) internal pure returns (int128 y) {
        if (x < type(int128).min || x > type(int128).max) {
            revert IHyperdrive.UnsafeCastToInt128();
        }
        y = int128(x);
    }
}
