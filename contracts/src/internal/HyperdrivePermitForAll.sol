// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IMultiTokenMetadata } from "../interfaces/IMultiTokenMetadata.sol";
import { HyperdriveMultiToken } from "./HyperdriveMultiToken.sol";

/// @author DELV
/// @title HyperdrivePermitForAll
/// @notice Implements the logic for `permitForAll` and exposes getters for the
///         EIP712 domain separator and `permitForAll` typehash.
/// @dev
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdrivePermitForAll is
    IMultiTokenMetadata,
    HyperdriveMultiToken
{
    /// @notice The typehash used to calculate the EIP712 hash for `permitForAll`.
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "PermitForAll(address owner,address spender,bool _approved,uint256 nonce,uint256 deadline)"
        );

    /// @notice This contract's EIP712 domain separator.
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @dev Computes the EIP712 domain separator and stores it as an immutable.
    constructor() {
        // NOTE: It's convenient to keep this in the `Hyperdrive.sol`
        //       entry-point to avoiding issues with initializing the domain
        //       separator with the contract address. If this is moved to one of
        //       the targets, the domain separator will need to be computed
        //       differently.
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /// @dev Allows a caller who is not the owner of an account to execute the
    ///      functionality of 'approve' for all assets with the owners signature.
    /// @param owner The owner of the account which is having the new approval set.
    /// @param spender The address which will be allowed to spend owner's tokens.
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
    function _permitForAll(
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
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
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
        if (signer != owner) revert IHyperdrive.InvalidSignature();

        // Increment the signature nonce.
        ++_nonces[owner];

        // Set the state.
        _isApprovedForAll[owner][spender] = _approved;

        // Emit an event to track approval
        emit ApprovalForAll(owner, spender, _approved);
    }
}
