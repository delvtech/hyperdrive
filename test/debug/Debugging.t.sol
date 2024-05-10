// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { console2 as console } from "forge-std/console2.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { BaseTest } from "test/utils/BaseTest.sol";
import { EtchingUtils } from "test/utils/EtchingUtils.sol";
import { Lib } from "test/utils/Lib.sol";

/// @author DELV
/// @title Debugging
/// @notice A test suite to help debugging on Sepolia or Mainnet.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract Debugging is BaseTest, EtchingUtils {
    using Lib for *;

    /// @dev A flag indicating whether or not the test should be skipped. This
    ///      should be set to false when debugging.
    bool internal constant SHOULD_SKIP = false;

    /// @dev The block to fork. If you're debugging a failing transaction, this
    ///      should be the block at which the transaction was failing. If you're
    ///      debugging a successful transaction, you may need to subtract one
    ///      from the block.
    uint256 internal constant FORK_BLOCK = 5875056;

    /// @dev The hyperdrive instance to connect to. If you're debugging a
    ///      Hyperdrive transaction, this should probably be the `to` address in
    ///      the failing transaction.
    IHyperdrive internal constant HYPERDRIVE =
        IHyperdrive(address(0xA2Ad31DaEbfE222dc96810898EF7FC239daAb580));

    /// @dev The sender to use in the debugging call. If you're debugging a
    ///      Hyperdrive transaction, this should probably be the `from`
    ///      address in the failing transaction.
    address internal constant SENDER =
        address(0x005BB73FddB8CE049eE366b50d2f48763E9Dc0De);

    /// @dev The value to use in the debugging call. If you're debugging a
    ///      Hyperdrive transaction, this should probably be the `value`
    ///      sent in the failing transaction.
    uint256 internal constant VALUE = 0;

    /// @dev The calldata to use in the debugging call. If you're debugging a
    ///      Hyperdrive transaction, this should probably be the calldata from
    ///      the failing transaction (remove the "0x" prefix from the calldata).
    bytes internal constant CALLDATA =
        hex"cba2e58d000000000000000000000000000000000000000000000000ebec21ee1da400000000000000000000000000000000000000000000000000000009a6802140858400000000000000000000000000000000000000000000000000009181dcef8eda0000000000000000000000000000000000000000000000000000000000000080000000000000000000000000005bb73fddb8ce049ee366b50d2f48763e9dc0de0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000000";

    function test_debug() external __sepolia_fork(FORK_BLOCK) {
        // Skip this test during regular execution.
        // vm.skip(SHOULD_SKIP);

        // Etch the hyperdrive instance to add console logs.
        etchHyperdrive(address(HYPERDRIVE));

        // Log a preamble.
        console.log("---------------");
        console.log("-- Debugging --");
        console.log("---------------");
        console.log("");
        console.log("[test_debug] Sending the debugging call...");
        console.log("");

        // Debugging the transaction.
        vm.startPrank(address(SENDER));
        (bool success, bytes memory returndata) = address(HYPERDRIVE).call{
            value: VALUE
        }(CALLDATA);

        // Log a summary.
        if (success) {
            console.log(
                "[test_debug] The call succeeded and returned the following returndata: %s",
                vm.toString(returndata)
            );
        } else {
            console.log(
                "[test_debug] The call failed and returned the following returndata: %s",
                vm.toString(returndata)
            );
        }
    }
}
