// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IMultiTokenEvents {
    /// @notice Emitted when tokens are transferred from one account to another.
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    /// @notice Emitted when an account changes the allowance for another
    ///         account.
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    /// @notice Emitted when an account changes the approval for all of its
    ///         tokens.
    event ApprovalForAll(
        address indexed account,
        address indexed operator,
        bool approved
    );
}
