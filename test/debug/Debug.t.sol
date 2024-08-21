// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { console2 as console } from "forge-std/console2.sol";
import { IHyperdriveCore } from "../../contracts/src/interfaces/IHyperdriveCore.sol";
import { IMultiTokenCore } from "../../contracts/src/interfaces/IMultiTokenCore.sol";
import { ETH } from "../../contracts/src/libraries/Constants.sol";
import { BaseTest } from "../utils/BaseTest.sol";
import { EtchingUtils } from "../utils/EtchingUtils.sol";
import { Lib } from "../utils/Lib.sol";

/// @author DELV
/// @title Debugging
/// @notice A test suite to help debugging on Sepolia or Mainnet.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract Debug is BaseTest, EtchingUtils {
    using Lib for *;

    /// @dev A minimal Ethereum transaction.
    struct Transaction {
        address to;
        address from;
        uint256 value;
        bytes data;
    }

    function test_debug() external {
        // Skip this test unless the debugging environment variable is set.
        vm.skip(!vm.envOr("DEBUG", false));

        // Set up the fork environment and get the appropriate transaction
        // details given the mode that we are using. If a tx hash was provided,
        // we default to using the transaction debugging mode. Otherwise, we
        // will see if the data was provided manually.
        Transaction memory tx_;
        string memory rpcURL = vm.envString("DEBUG_RPC_URL");
        bytes32 txHash = vm.envOr("TX_HASH", bytes32(0));
        if (txHash != bytes32(0)) {
            // Fork the chain specified by the debug RPC URL at the specified
            // transaction hash.
            uint256 forkId = vm.createFork(rpcURL);
            vm.selectFork(forkId);
            vm.rollFork(txHash);

            // Get the transaction details of the transaction. We assume that this
            // is a transaction to a Hyperdrive instance.
            tx_ = getTransaction(rpcURL, txHash);
        } else {
            // Fork the chain specified by the debug RPC URL at the specified
            // block height.
            uint256 forkId = vm.createFork(rpcURL);
            vm.selectFork(forkId);
            vm.rollFork(vm.envUint("BLOCK"));

            // Manually construct the transaction.
            tx_.to = vm.envAddress("TO");
            tx_.from = vm.envAddress("FROM");
            tx_.value = vm.envUint("VALUE");
            tx_.data = vm.envBytes("DATA");
        }

        // Debug the transaction.
        debug(tx_);
    }

    /// @dev Debugs the provided Hyperdrive transaction.
    /// @param _tx The transaction to debug.
    function debug(Transaction memory _tx) internal {
        // Etch the hyperdrive instance to add console logs.
        (
            string memory name,
            string memory kind,
            string memory version
        ) = etchHyperdrive(_tx.to);

        // Log a preamble with the Hyperdrive name, version, and the function
        // that will be called.
        console.log(
            "[test_debug] Found instance named %s of kind %s at version %s",
            name,
            kind,
            version
        );
        (string memory targetName, bool wasRecognized) = getTargetName(
            _tx.data
        );
        if (wasRecognized) {
            console.log('[test_debug] Simulating a call to "%s"', targetName);
        } else {
            console.log(
                "[test_debug] Simulating a call to an unrecognized function"
            );
        }

        // Debugging the transaction.
        vm.startPrank(_tx.from);
        (bool success, bytes memory returndata) = _tx.to.call{
            value: _tx.value
        }(_tx.data);

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

    /// @dev Gets the name of the function that was called with the provided
    ///      calldata.
    /// @param _data The transaction calldata.
    /// @return The name of the function that was called.
    /// @return A flag indicating whether or not the target name was
    ///         successfully found.
    function getTargetName(
        bytes memory _data
    ) internal pure returns (string memory, bool) {
        // Attempt to match the selector to one of the functions in the
        // Hyperdrive interface. If the selector doesn't match any of the
        // functions, we return a failure flag indicating that.
        bytes4 selector = bytes4(_data);
        if (selector == IHyperdriveCore.openLong.selector) {
            return ("openLong", true);
        } else if (selector == IHyperdriveCore.openShort.selector) {
            return ("openShort", true);
        } else if (selector == IHyperdriveCore.closeLong.selector) {
            return ("closeLong", true);
        } else if (selector == IHyperdriveCore.closeShort.selector) {
            return ("closeShort", true);
        } else if (selector == IHyperdriveCore.initialize.selector) {
            return ("initialize", true);
        } else if (selector == IHyperdriveCore.addLiquidity.selector) {
            return ("addLiquidity", true);
        } else if (selector == IHyperdriveCore.removeLiquidity.selector) {
            return ("removeLiquidity", true);
        } else if (
            selector == IHyperdriveCore.redeemWithdrawalShares.selector
        ) {
            return ("redeemWithdrawalShares", true);
        } else if (selector == IHyperdriveCore.checkpoint.selector) {
            return ("checkpoint", true);
        } else if (selector == IHyperdriveCore.collectGovernanceFee.selector) {
            return ("collectGovernanceFee", true);
        } else if (selector == IHyperdriveCore.pause.selector) {
            return ("pause", true);
        } else if (selector == IHyperdriveCore.setGovernance.selector) {
            return ("setGovernance", true);
        } else if (selector == IHyperdriveCore.setPauser.selector) {
            return ("setPauser", true);
        } else if (selector == IHyperdriveCore.sweep.selector) {
            return ("sweep", true);
        } else if (selector == IMultiTokenCore.transferFrom.selector) {
            return ("transferFrom", true);
        } else if (selector == IMultiTokenCore.transferFromBridge.selector) {
            return ("transferFromBridge", true);
        } else if (selector == IMultiTokenCore.setApproval.selector) {
            return ("setApproval", true);
        } else if (selector == IMultiTokenCore.setApprovalBridge.selector) {
            return ("setApprovalBridge", true);
        } else if (selector == IMultiTokenCore.setApprovalForAll.selector) {
            return ("setApprovalForAll", true);
        } else if (selector == IMultiTokenCore.batchTransferFrom.selector) {
            return ("batchTransferFrom", true);
        } else if (selector == IMultiTokenCore.permitForAll.selector) {
            return ("permitForAll", true);
        }
        return ("", false);
    }

    /// @dev Gets a transaction on a specified chain.
    /// @param _rpcURL The RPC URL to query.
    /// @param _txHash The transaction hash.
    /// @return tx_ The transaction.
    function getTransaction(
        string memory _rpcURL,
        bytes32 _txHash
    ) internal returns (Transaction memory tx_) {
        // Shell out to cast to make the RPC call.
        string[] memory command = new string[](6);
        command[0] = "cast";
        command[1] = "tx";
        command[2] = vm.toString(_txHash);
        command[3] = "--json";
        command[4] = "--rpc-url";
        command[5] = _rpcURL;
        string memory json = string(vm.ffi(command));

        // Parse the result json into the transaction.
        tx_.from = vm.parseJsonAddress(json, ".from");
        tx_.to = vm.parseJsonAddress(json, ".to");
        tx_.value = vm.parseJsonUint(json, ".value");
        tx_.data = vm.parseJsonBytes(json, ".input");

        return tx_;
    }
}
