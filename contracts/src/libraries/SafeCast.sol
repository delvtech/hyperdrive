// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

/// @notice Safe unsigned integer casting library that reverts on overflow.
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/SafeCastLib.sol)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeCast.sol)
library SafeCast {
    function toUint128(uint256 x) internal pure returns (uint128 y) {
        require(x < 1 << 128);

        y = uint128(x);
    }

    function toInt128(int256 x) internal pure returns (int128 y) {
        require(x >= type(int128).min && x <= type(int128).max);

        y = int128(x);
    }
}
