// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

interface IMultiTokenEvents {
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    event ApprovalForAll(
        address indexed account,
        address indexed operator,
        bool approved
    );
}
