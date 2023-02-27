// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import "forge-std/Vm.sol";

library Lib {
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
