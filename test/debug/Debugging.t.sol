// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { console2 as console } from "forge-std/console2.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { BaseTest } from "test/utils/BaseTest.sol";
import { EtchingUtils } from "test/utils/EtchingUtils.sol";

/// @author DELV
/// @title Debugging
/// @notice A test suite to help debugging on Sepolia or Mainnet.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract Debugging is BaseTest, EtchingUtils {
    /// @dev The block to fork. If you're debugging a failing transaction, this
    ///      should be the block at which the transaction was failing. If you're
    ///      debugging a successful transaction, you may need to subtract one
    ///      from the block.
    uint256 internal constant FORK_BLOCK = 5676348;

    /// @dev The hyperdrive instance to connect to. If you're debugging a
    ///      Hyperdrive transaction, this should probably be the `to` address in
    ///      the failing transaction.
    IHyperdrive internal constant HYPERDRIVE =
        IHyperdrive(address(0x392839dA0dACAC790bd825C81ce2c5E264D793a8));

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
    ///      the failing transaction (remove the "0x" prefix from the calldata.
    bytes internal constant CALLDATA =
        hex"cba2e58d0000000000000000000000000000000000000000000007d9a5405edc26fa36b50000000000000000000000000000000000000000000007d7f3c7d8d354cd71990000000000000000000000000000000000000000000000000de326f195450cd200000000000000000000000000000000000000000000000000000000000000800000000000000000000000002c76cc659ec83e36323f32e6a9789c29e7b56c4b0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000000";

    function test_debug() external __sepolia_fork(FORK_BLOCK) {
        // Etch the hyperdrive instance to add console logs.
        if (HYPERDRIVE.baseToken() == ETH) {
            etchStETHHyperdrive(address(HYPERDRIVE));
        } else {
            etchERC4626Hyperdrive(address(HYPERDRIVE));
        }

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
