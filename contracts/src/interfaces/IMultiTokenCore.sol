// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

interface IMultiTokenCore {
    /// Functions ///

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

    function batchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values
    ) external;

    function permitForAll(
        address owner,
        address spender,
        bool _approved,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
