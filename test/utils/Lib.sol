// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { console2 } from "forge-std/console2.sol";
import { stdMath } from "forge-std/StdMath.sol";
import { Vm, VmSafe } from "forge-std/Vm.sol";

library Lib {
    /// @dev Filters an array of longs for events that match the provided
    ///      selector.
    /// @param logs The array of logs to filter.
    /// @param selector The selector to filter for.
    /// @return filteredLogs The filtered array of logs.
    function filterLogs(
        VmSafe.Log[] memory logs,
        bytes32 selector
    ) internal pure returns (VmSafe.Log[] memory filteredLogs) {
        // Filter the logs.
        uint256 current = 0;
        filteredLogs = new VmSafe.Log[](logs.length);
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == selector) {
                filteredLogs[current++] = logs[i];
            }
        }

        // Trim the filtered logs array.
        assembly {
            mstore(filteredLogs, current)
        }
        return filteredLogs;
    }

    /// @dev Encodes a reason into a string error. This is useful for verifying
    ///      string errors in low-level calls.
    /// @param reason The reason to encode.
    /// @return The encoded string error.
    function toError(
        string memory reason
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(bytes4(keccak256("Error(string)")), reason);
    }

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
    ) internal pure {
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

    function normalizeToRange(
        uint256 value,
        uint256 minimum,
        uint256 maximum
    ) internal pure returns (uint256) {
        require(minimum <= maximum, "Lib: min > max");

        uint256 rangeSize = maximum - minimum + 1;
        uint256 modValue = value % rangeSize;

        return modValue + minimum;
    }

    function normalizeToRange(
        int256 value,
        int256 minimum,
        int256 maximum
    ) internal pure returns (int256) {
        require(minimum <= maximum, "Lib: min > max");

        int256 rangeSize = maximum - minimum + 1;
        int256 modValue = value % rangeSize;

        if (modValue < 0) {
            modValue += rangeSize;
        }

        return modValue + minimum;
    }

    function approxEq(
        uint256 a,
        uint256 b,
        uint256 tolerance
    ) internal pure returns (bool) {
        uint256 delta = stdMath.delta(a, b);
        return delta <= tolerance;
    }

    function approxEq(
        int256 a,
        int256 b,
        uint256 tolerance
    ) internal pure returns (bool) {
        uint256 delta = stdMath.delta(a, b);
        return delta <= tolerance;
    }

    function eq(bytes memory b1, bytes memory b2) public pure returns (bool) {
        return
            b1.length == b2.length &&
            keccak256(abi.encodePacked(b1)) == keccak256(abi.encodePacked(b2));
    }

    function neq(bytes memory b1, bytes memory b2) public pure returns (bool) {
        return
            b1.length != b2.length ||
            keccak256(abi.encodePacked(b1)) != keccak256(abi.encodePacked(b2));
    }

    function eq(string memory b1, string memory b2) public pure returns (bool) {
        return
            bytes(b1).length == bytes(b2).length &&
            keccak256(abi.encodePacked(b1)) == keccak256(abi.encodePacked(b2));
    }

    function eq(
        address[] memory b1,
        address[] memory b2
    ) public pure returns (bool) {
        return
            b1.length == b2.length &&
            keccak256(abi.encodePacked(b1)) == keccak256(abi.encodePacked(b2));
    }
}
