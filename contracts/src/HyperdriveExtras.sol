// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { HyperdriveAdmin } from "./HyperdriveAdmin.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
import { HyperdriveCheckpoint } from "./HyperdriveCheckpoint.sol";
import { HyperdriveLong } from "./HyperdriveLong.sol";
import { HyperdriveLP } from "./HyperdriveLP.sol";
import { HyperdriveShort } from "./HyperdriveShort.sol";

// FIXME: Natspec
abstract contract HyperdriveExtras is
    HyperdriveBase,
    HyperdriveAdmin,
    HyperdriveLP,
    HyperdriveLong,
    HyperdriveShort,
    HyperdriveCheckpoint
{
    /// @notice Instantiates a Hyperdrive extras contract.
    /// @param _config The configuration of the pool.
    /// @param _linkerCodeHash The code hash of the linker contract.
    /// @param _linkerFactory The address of the linker factory.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash,
        address _linkerFactory
    ) HyperdriveBase(_config, _linkerCodeHash, _linkerFactory) {}

    /// Admin ///

    /// @notice This function collects the governance fees accrued by the pool.
    /// @param _options The options that configure how the fees are settled.
    /// @return proceeds The amount of base collected.
    function collectGovernanceFee(
        IHyperdrive.Options calldata _options
    ) external returns (uint256 proceeds) {
        return _collectGovernanceFee(_options);
    }

    /// @notice Allows an authorized address to pause this contract.
    /// @param _status True to pause all deposits and false to unpause them.
    function pause(bool _status) external {
        _pause(_status);
    }

    /// @notice Allows governance to change governance.
    /// @param _who The new governance address.
    function setGovernance(address _who) external {
        _setGovernance(_who);
    }

    /// @notice Allows governance to change the pauser status of an address.
    /// @param who The address to change.
    /// @param status The new pauser status.
    function setPauser(address who, bool status) external {
        _setPauser(who, status);
    }

    /// Token ///

    /// @notice Transfers an amount of assets from the source to the destination.
    /// @param tokenID The token identifier.
    /// @param from The address who's balance will be reduced.
    /// @param to The address who's balance will be increased.
    /// @param amount The amount of token to move.
    function transferFrom(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount
    ) external {
        // Forward to our internal version
        _transferFrom(tokenID, from, to, amount, msg.sender);
    }

    /// @notice Permissioned transfer for the bridge to access, only callable by
    ///         the ERC20 linking bridge.
    /// @param tokenID The token identifier.
    /// @param from The address who's balance will be reduced.
    /// @param to The address who's balance will be increased.
    /// @param amount The amount of token to move.
    /// @param caller The msg.sender from the bridge.
    function transferFromBridge(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount,
        address caller
    ) external onlyLinker(tokenID) {
        // Route to our internal transfer
        _transferFrom(tokenID, from, to, amount, caller);
    }

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
    ) external onlyLinker(tokenID) {
        _setApproval(tokenID, operator, amount, caller);
    }

    /// @notice Allows a user to approve an operator to use all of their assets.
    /// @param operator The eth address which can access the caller's assets.
    /// @param approved True to approve, false to remove approval.
    function setApprovalForAll(address operator, bool approved) external {
        // set the appropriate state
        _isApprovedForAll[msg.sender][operator] = approved;
        // Emit an event to track approval
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @notice Allows a user to set an approval for an individual asset with
    ///         specific amount.
    /// @param tokenID The asset to approve the use of
    /// @param operator The address who will be able to use the tokens
    /// @param amount The max tokens the approved person can use, setting to
    ///        uint256.max will cause the value to never decrement [saving gas
    ///        on transfer].
    function setApproval(
        uint256 tokenID,
        address operator,
        uint256 amount
    ) external {
        _setApproval(tokenID, operator, amount, msg.sender);
    }

    /// @notice Transfers several assets from one account to another
    /// @param from the source account
    /// @param to the destination account
    /// @param ids The array of token ids of the asset to transfer
    /// @param values The amount of each token to transfer
    function batchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values
    ) external {
        _batchTransferFrom(from, to, ids, values);
    }

    /// @notice Allows a caller who is not the owner of an account to execute the
    ///      functionality of 'approve' for all assets with the owners signature.
    /// @param owner The owner of the account which is having the new approval set.
    /// @param spender The address which will be allowed to spend owner's tokens
    /// @param _approved A boolean of the approval status to set to
    /// @param deadline The timestamp which the signature must be submitted by
    ///        to be valid.
    /// @param v Extra ECDSA data which allows public key recovery from
    ///        signature assumed to be 27 or 28.
    /// @param r The r component of the ECDSA signature
    /// @param s The s component of the ECDSA signature
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
    ) external {
        _permitForAll(owner, spender, _approved, deadline, v, r, s);
    }
}
