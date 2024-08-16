// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveEvents } from "../interfaces/IHyperdriveEvents.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";

/// @author DELV
/// @title HyperdriveMultiToken
/// @notice Implements the MultiToken accounting that Hyperdrive uses to track
///         user's positions. MultiToken maintains a set of balances and
///         approvals for a list of sub-tokens specified by an asset ID. This
///         token is mostly ERC1155 compliant; however, we remove on transfer
///         callbacks and safe transfer because of the risk of external calls to
///         untrusted code.
/// @dev Our architecture maintains ERC20 compatibility by allowing users to
///      access their balances and approvals through ERC20 forwarding contracts
///      deployed by the registered forwarder factory. To ensure that only the
///      ERC20 forwarders can call the bridge endpoints, we verify that the
///      create2 pre-image of the caller address is the ERC20 forwarder bytecode
///      and the token ID.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveMultiToken is IHyperdriveEvents, HyperdriveBase {
    /// @notice This modifier checks the caller is the create2 validated
    ///         ERC20 bridge.
    /// @param tokenID The internal token identifier.
    modifier onlyLinker(uint256 tokenID) {
        // If the caller does not match the address hash, we revert because it
        // is not allowed to access permissioned methods.
        if (msg.sender != _deriveForwarderAddress(tokenID)) {
            revert IHyperdrive.InvalidERC20Bridge();
        }

        // Execute the following function.
        _;
    }

    /// @dev Transfers several assets from one account to another.
    /// @param from The source account.
    /// @param to The destination account.
    /// @param ids The array of token ids of the asset to transfer.
    /// @param values The amount of each token to transfer.
    function _batchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values
    ) internal {
        // Checks for inconsistent addresses.
        if (from == address(0) || to == address(0)) {
            revert IHyperdrive.RestrictedZeroAddress();
        }

        // Check for inconsistent length.
        if (ids.length != values.length) {
            revert IHyperdrive.BatchInputLengthMismatch();
        }

        // Call internal transfer for each asset.
        for (uint256 i = 0; i < ids.length; i++) {
            _transferFrom(ids[i], from, to, values[i], msg.sender);
        }
    }

    /// @dev Performs the actual transfer logic.
    /// @param tokenID The token identifier.
    /// @param from The address whose balance will be reduced.
    /// @param to The address whose balance will be increased.
    /// @param amount The amount of token to move.
    /// @param caller The msg.sender or the caller of the ERC20Forwarder.
    function _transferFrom(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount,
        address caller
    ) internal {
        // Checks for inconsistent addresses.
        if (from == address(0) || to == address(0)) {
            revert IHyperdrive.RestrictedZeroAddress();
        }

        // If the transaction sender is calling no need for further validation.
        if (caller != from) {
            // Or if the transaction sender can access all user assets, no need
            // for more validation.
            if (!_isApprovedForAll[from][caller]) {
                // Finally we load the per asset approval.
                uint256 approved = _perTokenApprovals[tokenID][from][caller];
                // If it is not an infinite approval
                if (approved != type(uint256).max) {
                    // Then we subtract the amount the caller wants to use
                    // from how much they can use, reverting on underflow.
                    // NOTE: This reverts without message for unapproved callers
                    // when debugging that's the likely source of any mystery
                    // reverts.
                    _perTokenApprovals[tokenID][from][caller] -= amount;
                }
            }
        }

        // Reaching this point implies the transfer is authorized so we remove
        // from the source and add to the destination.
        _balanceOf[tokenID][from] -= amount;
        _balanceOf[tokenID][to] += amount;
        emit TransferSingle(caller, from, to, tokenID, amount);
    }

    /// @notice Sets the approval for a sub-token.
    /// @param tokenID The asset to approve the use of.
    /// @param operator The address who will be able to use the tokens.
    /// @param amount The max tokens the approved person can use, setting to
    ///               uint256.max will cause the value to never decrement
    ///               [saving gas on transfer].
    /// @param caller The eth address which initiated the approval call.
    function _setApproval(
        uint256 tokenID,
        address operator,
        uint256 amount,
        address caller
    ) internal {
        _perTokenApprovals[tokenID][caller][operator] = amount;

        // Emit an event to track approval.
        emit Approval(caller, operator, amount);
    }

    /// @notice Minting function to create tokens.
    /// @param tokenID The asset type to create.
    /// @param to The address whose balance to increase.
    /// @param amount The number of tokens to create.
    /// @dev Must be used from inheriting contracts.
    function _mint(
        uint256 tokenID,
        address to,
        uint256 amount
    ) internal virtual {
        _balanceOf[tokenID][to] += amount;
        _totalSupply[tokenID] += amount;

        // Emit an event to track minting.
        emit TransferSingle(msg.sender, address(0), to, tokenID, amount);
    }

    /// @notice Burning function to remove tokens.
    /// @param tokenID The asset type to remove.
    /// @param from The address whose balance to decrease.
    /// @param amount The number of tokens to remove.
    /// @dev Must be used from inheriting contracts.
    function _burn(uint256 tokenID, address from, uint256 amount) internal {
        // Check to see if the balance is sufficient. If it isn't, throw an
        // insufficient balance error.
        if (_balanceOf[tokenID][from] < amount) {
            revert IHyperdrive.InsufficientBalance();
        }

        // Decrement from the source and supply.
        unchecked {
            _balanceOf[tokenID][from] -= amount;
        }
        _totalSupply[tokenID] -= amount;

        // Emit an event to track burning.
        emit TransferSingle(msg.sender, from, address(0), tokenID, amount);
    }

    /// @dev Allows a caller who is not the owner of an account to execute the
    ///      functionality of 'approve' for all assets with the owners signature.
    /// @param domainSeparator The EIP712 domain separator for this contract.
    /// @param permitTypehash The EIP712 typehash for the permit data.
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
    function _permitForAll(
        bytes32 domainSeparator,
        bytes32 permitTypehash,
        address owner,
        address spender,
        bool _approved,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        // Require that the signature is not expired.
        if (block.timestamp > deadline) {
            revert IHyperdrive.ExpiredDeadline();
        }

        // Require that the owner is not zero.
        if (owner == address(0)) {
            revert IHyperdrive.RestrictedZeroAddress();
        }

        // Check that the signature is valid and recovers to the owner.
        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        permitTypehash,
                        owner,
                        spender,
                        _approved,
                        _nonces[owner],
                        deadline
                    )
                )
            )
        );
        address signer = ecrecover(structHash, v, r, s);
        if (signer != owner) {
            revert IHyperdrive.InvalidSignature();
        }

        // Increment the signature nonce.
        unchecked {
            ++_nonces[owner];
        }

        // Set the state.
        _isApprovedForAll[owner][spender] = _approved;

        // Emit an event to track approval.
        emit ApprovalForAll(owner, spender, _approved);
    }

    /// @notice Derive the ERC20 forwarder address for a provided `tokenId`.
    /// @param tokenId Token Id of the token whose forwarder contract address
    ///        need to derived.
    /// @return Address of the ERC20 forwarder contract.
    function _deriveForwarderAddress(
        uint256 tokenId
    ) internal view returns (address) {
        // Get the salt which is used by the deploying contract.
        bytes32 salt = keccak256(abi.encode(address(this), tokenId));

        // Perform the hash which determines the address of a create2 deployment.
        bytes32 addressBytes = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                _linkerFactory,
                salt,
                _linkerCodeHash
            )
        );
        return address(uint160(uint256(addressBytes)));
    }
}
