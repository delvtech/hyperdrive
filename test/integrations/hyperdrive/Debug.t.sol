// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { console2 as console } from "forge-std/console2.sol";
import { EtchingUtils } from "test/utils/EtchingUtils.sol";
import { HyperdriveTest } from "test/utils/HyperdriveTest.sol";

contract Debug is HyperdriveTest, EtchingUtils {
    function test_debug() external __sepolia_fork(5669822) {
        // Etch the hyperdrive instance to add console logs.
        address hyperdrive = address(
            0xff33bd6d7ED4119c99C310F3e5f0Fa467796Ee23
        );
        etchStETHHyperdrive(hyperdrive);

        // Make the failed call.
        vm.startPrank(address(0x0076b154e60BF0E9088FcebAAbd4A778deC5ce2c));
        (bool success, ) = hyperdrive.call(
            hex"cba2e58d0000000000000000000000000000000000000000000000220753ac4022f618be000000000000000000000000000000000000000000000021ce4c1a12ccde2ed00000000000000000000000000000000000000000000000000de10e96f727627a00000000000000000000000000000000000000000000000000000000000000800000000000000000000000000076b154e60bf0e9088fcebaabd4a778dec5ce2c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000000"
        );
        require(!success, "the transaction succeeded");
    }
}
