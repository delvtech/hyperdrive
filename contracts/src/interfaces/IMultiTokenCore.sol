// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IMultiTokenCore {
    /// @notice Transfers an amount of assets from the source to the destination.
    /// @param tokenID The token identifier.
    /// @param from The address whose balance will be reduced.
    /// @param to The address whose balance will be increased.
    /// @param amount The amount of token to move.
    function transferFrom(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount
    ) external;

    /// @notice Permissioned transfer for the bridge to access, only callable by
    ///         the ERC20 linking bridge.
    /// @param tokenID The token identifier.
    /// @param from The address whose balance will be reduced.
    /// @param to The address whose balance will be increased.
    /// @param amount The amount of token to move.
    /// @param caller The msg.sender or the caller of the ERC20Forwarder.
    function transferFromBridge(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount,
        address caller
    ) external;

    /// @notice Allows a user to set an approval for an individual asset with
    ///         specific amount.
    /// @param tokenID The asset to approve the use of.
    /// @param operator The address who will be able to use the tokens.
    /// @param amount The max tokens the approved person can use, setting to
    ///        uint256.max will cause the value to never decrement (saving gas
    ///        on transfer).
    function setApproval(
        uint256 tokenID,
        address operator,
        uint256 amount
    ) external;

    /// @notice Allows the compatibility linking contract to forward calls to
    ///         set asset approvals.
    /// @param tokenID The asset to approve the use of.
    /// @param operator The address who will be able to use the tokens.
    /// @param amount The max tokens the approved person can use, setting to
    ///        uint256.max will cause the value to never decrement [saving gas
    ///        on transfer].
    /// @param caller The eth address which called the linking contract.
    function setApprovalBridge(
        uint256 tokenID,
        address operator,
        uint256 amount,
        address caller
    ) external;

    /// @notice Allows a user to approve an operator to use all of their assets.
    /// @param operator The eth address which can access the caller's assets.
    /// @param approved True to approve, false to remove approval.
    function setApprovalForAll(address operator, bool approved) external;

    /// @notice Transfers several assets from one account to another.
    /// @param from The source account.
    /// @param to The destination account.
    /// @param ids The array of token ids of the asset to transfer.
    /// @param values The amount of each token to transfer.
    function batchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values
    ) external;

    /// @notice Allows a caller who is not the owner of an account to execute the
    ///         functionality of 'approve' for all assets with the owner's
    ///         signature.
    /// @param owner The owner of the account which is having the new approval set.
    /// @param spender The address which will be allowed to spend owner's tokens.
    /// @param _approved A boolean of the approval status to set to.
    /// @param deadline The timestamp which the signature must be submitted by
    ///        to be valid.
    /// @param v Extra ECDSA data which allows public key recovery from
    ///        signature assumed to be 27 or 28.
    /// @param r The r component of the ECDSA signature.
    /// @param s The s component of the ECDSA signature.
    /// @dev The signature for this function follows EIP 712 standard and should
    ///      be generated with the eth_signTypedData JSON RPC call instead of
    ///      the eth_sign JSON RPC call. If using out of date parity signing
    ///      libraries the v component may need to be adjusted. Also it is very
    ///      rare but possible for v to be other values, those values are not
    ///      supported.
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
