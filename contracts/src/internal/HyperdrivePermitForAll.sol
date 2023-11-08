// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { HyperdriveMultiToken } from "./HyperdriveMultiToken.sol";

// FIXME: Natspec
abstract contract HyperdrivePermitForAll is HyperdriveMultiToken {
    // FIXME: Natspec
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "PermitForAll(address owner,address spender,bool _approved,uint256 nonce,uint256 deadline)"
        );

    // FIXME: Natspec
    bytes32 public immutable DOMAIN_SEPARATOR;

    constructor() {
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

        // Check that the signature is valid.
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
