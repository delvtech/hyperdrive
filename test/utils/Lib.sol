// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import "forge-std/Vm.sol";

library Lib {
    /// @dev Converts a signed integer to a string with a specified amount of
    ///      decimals. In the event that the integer doesn't have any digits to
    ///      the left of the decimal place, zeros will be filled in.
    /// @param num The integer to be converted.
    /// @param decimals The number of decimal places to add. If zero, the the
    ///        decimal point is excluded.
    /// @return result The stringified integer.
    function toString(
        int256 num,
        uint256 decimals
    ) internal pure returns (string memory result) {
        // We overallocate memory for the string. The maximum number of decimals
        // that a int256 can hold is log_10(2 ^ 255) which is approximately
        // 76.76. Thus, the string has a maximum length of 77 without the
        // decimal point and minus sign.
        uint256 maxStringLength = 79;
        bytes memory rawResult = new bytes(maxStringLength);

        // Negative integers don't play nicely with the EVM's modular arithmetic
        // as the result of the modulus is either 0 or a negative number. With
        // this in mind, we convert to a positive number to make string
        // conversion easier.
        bool isNegative = num < 0;
        num = num < 0 ? -num : num;

        // Loop through the integer and add each digit to the raw result,
        // starting at the end of the string and working towards the beginning.
        rawResult[maxStringLength - 1] = bytes1(
            uint8(uint256((num % 10) + 48))
        );
        num /= 10;
        uint256 digits = 1;
        while (num != 0 || digits <= decimals + 1) {
            if (decimals > 0 && digits == decimals) {
                rawResult[maxStringLength - digits - 1] = ".";
            } else {
                rawResult[maxStringLength - digits - 1] = bytes1(
                    uint8(uint256((num % 10) + 48))
                );
                num /= 10;
            }
            digits++;
        }

        // If necessary, add the minus sign to the beginning of the stringified
        // integer.
        if (isNegative) {
            rawResult[maxStringLength - digits - 1] = "-";
            digits++;
        }

        // Point the string result to the beginning of the stringified integer
        // and update the length.
        assembly {
            result := add(rawResult, sub(sub(maxStringLength, digits), 1))
            mstore(result, add(digits, 1))
        }
        return result;
    }

    /// @dev Converts an unsigned integer to a string with a specified amount of
    ///      decimals. In the event that the integer doesn't have any digits to
    ///      the left of the decimal place, zeros will be filled in.
    /// @param num The integer to be converted.
    /// @param decimals The number of decimal places to add. If zero, the the
    ///        decimal point is excluded.
    /// @return result The stringified integer.
    function toString(
        uint256 num,
        uint256 decimals
    ) internal pure returns (string memory result) {
        // We overallocate memory for the string. The maximum number of decimals
        // that a uint256 can hold is log_10(2 ^ 256) which is approximately
        // 77.06. Thus, the string has a maximum length of 78.
        uint256 maxStringLength = 79;
        bytes memory rawResult = new bytes(maxStringLength);

        // Loop through the integer and add each digit to the raw result,
        // starting at the end of the string and working towards the beginning.
        rawResult[maxStringLength - 1] = bytes1(uint8((num % 10) + 48));
        num /= 10;
        uint256 digits = 1;
        while (num != 0 || digits <= decimals + 1) {
            if (decimals > 0 && digits == decimals) {
                rawResult[maxStringLength - digits - 1] = ".";
            } else {
                rawResult[maxStringLength - digits - 1] = bytes1(
                    uint8((num % 10) + 48)
                );
                num /= 10;
            }
            digits++;
        }

        // Point the string result to the beginning of the stringified integer
        // and update the length.
        assembly {
            result := add(rawResult, sub(sub(maxStringLength, digits), 1))
            mstore(result, add(digits, 1))
        }
        return result;
    }

    function logArray(
        string memory prelude,
        uint256[] memory array
    ) internal view {
        console2.log(prelude, "[");
        for (uint256 i = 0; i < array.length; i++) {
            if (i < array.length - 1) {
                console2.log("        ", array[i], ",");
            } else {
                console2.log("        ", array[i]);
            }
        }
        console2.log("    ]");
        console2.log("");
    }

    function eq(bytes memory b1, bytes memory b2) public pure returns (bool) {
        return
            keccak256(abi.encodePacked(b1)) == keccak256(abi.encodePacked(b2));
    }

    function neq(bytes memory b1, bytes memory b2) public pure returns (bool) {
        return
            keccak256(abi.encodePacked(b1)) != keccak256(abi.encodePacked(b2));
    }
}
