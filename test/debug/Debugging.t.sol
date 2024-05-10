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
    bool internal constant SHOULD_SKIP = true;

    /// @dev The block to fork. If you're debugging a failing transaction, this
    ///      should be the block at which the transaction was failing. If you're
    ///      debugging a successful transaction, you may need to subtract one
    ///      from the block.
    uint256 internal constant FORK_BLOCK = 5876130;

    /// @dev The hyperdrive instance to connect to. If you're debugging a
    ///      Hyperdrive transaction, this should probably be the `to` address in
    ///      the failing transaction.
    IHyperdrive internal constant HYPERDRIVE =
        IHyperdrive(address(0xF2A8f3dcc019FD8F3EF286fe88F7efdd0c4D4b0c));

    /// @dev The sender to use in the debugging call. If you're debugging a
    ///      Hyperdrive transaction, this should probably be the `from`
    ///      address in the failing transaction.
    address internal constant SENDER =
        address(0x2C76cc659ec83E36323f32E6a9789C29e7b56c4B);

    /// @dev The value to use in the debugging call. If you're debugging a
    ///      Hyperdrive transaction, this should probably be the `value`
    ///      sent in the failing transaction.
    uint256 internal constant VALUE = 0;

    /// @dev The calldata to use in the debugging call. If you're debugging a
    ///      Hyperdrive transaction, this should probably be the calldata from
    ///      the failing transaction (remove the "0x" prefix from the calldata).
    bytes internal constant CALLDATA =
        hex"cba2e58d00000000000000000000000000000000000000000000006c6b935b8bbd400000000000000000000000000000000000000000000000000044c704eb74e081ea6600000000000000000000000000000000000000000000000008d2495c9d20228d00000000000000000000000000000000000000000000000000000000000000800000000000000000000000002c76cc659ec83e36323f32e6a9789c29e7b56c4b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000000";

    function test_debug() external __sepolia_fork(FORK_BLOCK) {
        // Skip this test during regular execution.
        vm.skip(SHOULD_SKIP);

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
