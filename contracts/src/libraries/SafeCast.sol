/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

/// @notice Safe unsigned integer casting library that reverts on overflow.
/// @author Inspired by Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/SafeCastLib.sol)
/// @author Inspired by OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeCast.sol)
library SafeCast {
    function toUint128(uint256 x) internal pure returns (uint128 y) {
    if (!(x < 1 << 128)) {
       revert IHyperdrive.UnsafeCastToUint128();
    }

        y = uint128(x);
    }

    function toInt128(int256 x) internal pure returns (int128 y) {
        if(!(x >= type(int128).min && x <= type(int128).max)){
            revert IHyperdrive.UnsafeCastToInt128();
        }

        y = int128(x);
    }
}
