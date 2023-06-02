// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

interface IMultiTokenWrite {
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

    function transferFrom(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount
    ) external;

    function transferFromBridge(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount,
        address caller
    ) external;

    function setApproval(
        uint256 tokenID,
        address operator,
        uint256 amount
    ) external;

    function setApprovalBridge(
        uint256 tokenID,
        address operator,
        uint256 amount,
        address caller
    ) external;

    function setApprovalForAll(address operator, bool approved) external;
}
