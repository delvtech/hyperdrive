// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { IERC1155Receiver } from "openzeppelin/interfaces/IERC1155Receiver.sol";
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
    /// @param _tokenID The internal token identifier.
    modifier onlyLinker(uint256 _tokenID) {
        // If the caller does not match the address hash, we revert because it
        // is not allowed to access permissioned methods.
        if (msg.sender != _deriveForwarderAddress(_tokenID)) {
            revert IHyperdrive.InvalidERC20Bridge();
        }

        // Execute the following function.
        _;
    }

    /// @dev Transfers several assets from one account to another.
    /// @param _from The source account.
    /// @param _to The destination account.
    /// @param _ids The array of token ids of the asset to transfer.
    /// @param _values The amount of each token to transfer.
    function _batchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _values
    ) internal {
        // Checks for inconsistent addresses.
        if (_from == address(0) || _to == address(0)) {
            revert IHyperdrive.RestrictedZeroAddress();
        }

        // Check for inconsistent length.
        if (_ids.length != _values.length) {
            revert IHyperdrive.BatchInputLengthMismatch();
        }

        // Call internal transfer for each asset.
        for (uint256 i = 0; i < _ids.length; i++) {
            _transferFrom(_ids[i], _from, _to, _values[i], msg.sender);
        }
    }

    /// @dev Performs the actual transfer logic.
    /// @param _tokenID The token identifier.
    /// @param _from The address whose balance will be reduced.
    /// @param _to The address whose balance will be increased.
    /// @param _amount The amount of token to move.
    /// @param _caller The msg.sender or the caller of the ERC20Forwarder.
    function _transferFrom(
        uint256 _tokenID,
        address _from,
        address _to,
        uint256 _amount,
        address _caller
    ) internal {
        // Checks for inconsistent addresses.
        if (_from == address(0) || _to == address(0)) {
            revert IHyperdrive.RestrictedZeroAddress();
        }

        // If the transaction sender is calling no need for further validation.
        if (_caller != _from) {
            // Or if the transaction sender can access all user assets, no need
            // for more validation.
            if (!_isApprovedForAll[_from][_caller]) {
                // Finally we load the per asset approval.
                uint256 approved = _perTokenApprovals[_tokenID][_from][_caller];
                // If it is not an infinite approval
                if (approved != type(uint256).max) {
                    // Then we subtract the amount the caller wants to use
                    // from how much they can use, reverting on underflow.
                    // NOTE: This reverts without message for unapproved callers
                    // when debugging that's the likely source of any mystery
                    // reverts.
                    _perTokenApprovals[_tokenID][_from][_caller] -= _amount;
                }
            }
        }

        // Reaching this point implies the transfer is authorized so we remove
        // from the source and add to the destination.
        _balanceOf[_tokenID][_from] -= _amount;
        _balanceOf[_tokenID][_to] += _amount;
        emit TransferSingle(_caller, _from, _to, _tokenID, _amount);
    }

    /// @dev Safely transfers tokens, checking if recipient is a contract and
    ///      can handle ERC1155 tokens.
    /// @param _from The source address.
    /// @param _to The destination address.
    /// @param _id The token identifier.
    /// @param _amount The amount to transfer.
    /// @param _data Additional data to pass to recipient if it's a contract.
    function _safeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount,
        bytes calldata _data
    ) internal nonReentrant {
        // Perform the regular transfer first.
        _transferFrom(_id, _from, _to, _amount, msg.sender);

        // If the destination is a contract, verify it can handle ERC1155 tokens.
        if (_to.code.length > 0) {
            try
                IERC1155Receiver(_to).onERC1155Received(
                    msg.sender,
                    _from,
                    _id,
                    _amount,
                    _data
                )
            returns (bytes4 response) {
                if (response != IERC1155Receiver.onERC1155Received.selector) {
                    revert IHyperdrive.ERC1155InvalidReceiver();
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert IHyperdrive.ERC1155InvalidReceiver();
            }
        }
    }

    /// @dev Safely transfers multiple tokens in a batch.
    /// @param _from The source address.
    /// @param _to The destination address.
    /// @param _ids Array of token identifiers.
    /// @param _amounts Array of amounts to transfer for each token.
    /// @param _data Additional data to pass to recipient if it's a contract.
    function _safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        bytes memory _data
    ) internal nonReentrant {
        // Perform the regular batch transfer first.
        _batchTransferFrom(_from, _to, _ids, _amounts);

        // If the destination is a contract, verify it can handle ERC1155 tokens
        if (_to.code.length > 0) {
            try
                IERC1155Receiver(_to).onERC1155BatchReceived(
                    msg.sender,
                    _from,
                    _ids,
                    _amounts,
                    _data
                )
            returns (bytes4 response) {
                if (
                    response != IERC1155Receiver.onERC1155BatchReceived.selector
                ) {
                    revert IHyperdrive.ERC1155InvalidReceiver();
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert IHyperdrive.ERC1155InvalidReceiver();
            }
        }
    }

    /// @notice Sets the approval for a sub-token.
    /// @param _tokenID The asset to approve the use of.
    /// @param _operator The address who will be able to use the tokens.
    /// @param _amount The max tokens the approved person can use, setting to
    ///        uint256.max will cause the value to never decrement (saving gas
    ///        on transfer).
    /// @param _caller The eth address which initiated the approval call.
    function _setApproval(
        uint256 _tokenID,
        address _operator,
        uint256 _amount,
        address _caller
    ) internal {
        _perTokenApprovals[_tokenID][_caller][_operator] = _amount;

        // Emit an event to track approval.
        emit Approval(_caller, _operator, _amount);
    }

    /// @notice Minting function to create tokens.
    /// @param _tokenID The asset type to create.
    /// @param _to The address whose balance to increase.
    /// @param _amount The number of tokens to create.
    /// @dev Must be used from inheriting contracts.
    function _mint(
        uint256 _tokenID,
        address _to,
        uint256 _amount
    ) internal virtual {
        _balanceOf[_tokenID][_to] += _amount;
        _totalSupply[_tokenID] += _amount;

        // Emit an event to track minting.
        emit TransferSingle(msg.sender, address(0), _to, _tokenID, _amount);
    }

    /// @notice Burning function to remove tokens.
    /// @param _tokenID The asset type to remove.
    /// @param _from The address whose balance to decrease.
    /// @param _amount The number of tokens to remove.
    /// @dev Must be used from inheriting contracts.
    function _burn(uint256 _tokenID, address _from, uint256 _amount) internal {
        // Check to see if the balance is sufficient. If it isn't, throw an
        // insufficient balance error.
        if (_balanceOf[_tokenID][_from] < _amount) {
            revert IHyperdrive.InsufficientBalance();
        }

        // Decrement from the source and supply.
        unchecked {
            _balanceOf[_tokenID][_from] -= _amount;
        }
        _totalSupply[_tokenID] -= _amount;

        // Emit an event to track burning.
        emit TransferSingle(msg.sender, _from, address(0), _tokenID, _amount);
    }

    /// @dev Allows a caller who is not the owner of an account to execute the
    ///      functionality of 'approve' for all assets with the owners signature.
    /// @param _domainSeparator The EIP712 domain separator for this contract.
    /// @param _permitTypehash The EIP712 typehash for the permit data.
    /// @param _owner The owner of the account which is having the new approval set.
    /// @param _spender The address which will be allowed to spend owner's tokens.
    /// @param _approved A boolean of the approval status to set to.
    /// @param _deadline The timestamp which the signature must be submitted by
    ///        _to be valid.
    /// @param _v Extra ECDSA data which allows public key recovery from
    ///        _signature assumed to be 27 or 28.
    /// @param _r The r component of the ECDSA signature.
    /// @param _s The s component of the ECDSA signature.
    /// @dev The signature for this function follows EIP 712 standard and should
    ///      be generated with the eth_signTypedData JSON RPC call instead of
    ///      the eth_sign JSON RPC call. If using out of date parity signing
    ///      libraries the v component may need to be adjusted. Also it is very
    ///      rare but possible for v to be other values, those values are not
    ///      supported.
    function _permitForAll(
        bytes32 _domainSeparator,
        bytes32 _permitTypehash,
        address _owner,
        address _spender,
        bool _approved,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal {
        // Require that the signature is not expired.
        if (block.timestamp > _deadline) {
            revert IHyperdrive.ExpiredDeadline();
        }

        // Require that the owner is not zero.
        if (_owner == address(0)) {
            revert IHyperdrive.RestrictedZeroAddress();
        }

        // Check that the signature is valid and recovers to the owner.
        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparator,
                keccak256(
                    abi.encode(
                        _permitTypehash,
                        _owner,
                        _spender,
                        _approved,
                        _nonces[_owner],
                        _deadline
                    )
                )
            )
        );
        address signer = ecrecover(structHash, _v, _r, _s);
        if (signer != _owner) {
            revert IHyperdrive.InvalidSignature();
        }

        // Increment the signature nonce.
        unchecked {
            ++_nonces[_owner];
        }

        // Set the state.
        _isApprovedForAll[_owner][_spender] = _approved;

        // Emit an event to track approval.
        emit ApprovalForAll(_owner, _spender, _approved);
    }

    /// @notice Derive the ERC20 forwarder address for a provided `tokenId`.
    /// @param _tokenId Token Id of the token whose forwarder contract address
    ///        need to derived.
    /// @return Address of the ERC20 forwarder contract.
    function _deriveForwarderAddress(
        uint256 _tokenId
    ) internal view returns (address) {
        // Get the salt which is used by the deploying contract.
        bytes32 salt = keccak256(abi.encode(address(this), _tokenId));

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
