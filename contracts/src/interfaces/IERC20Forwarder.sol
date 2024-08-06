// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20 } from "./IERC20.sol";
import { IMultiToken } from "./IMultiToken.sol";

interface IERC20Forwarder is IERC20 {
    /// Errors ///

    /// @notice Thrown when a permit signature is submitted after its deadline
    ///         has expired.
    error ExpiredDeadline();

    /// @notice Thrown when a permit signature doesn't recover to the owner's
    ///         address.
    error InvalidSignature();

    /// @notice Thrown when a permit signature recovers to the zero address.
    error RestrictedZeroAddress();

    /// Functions ///

    /// @notice This function allows a caller who is not the owner of an account
    ///         to execute the functionality of 'approve' with the owner's
    ///         signature.
    /// @dev The signature for this function follows EIP712 standard and should
    ///      be generated with the eth_signTypedData JSON RPC call instead of
    ///      the eth_sign JSON RPC call. If using out of date parity signing
    ///      libraries the v component may need to be adjusted. Also it is very
    ///      rare but possible for v to be other values. Those values are not
    ///      supported.
    /// @param owner The owner of the account which is having the new approval set.
    /// @param spender The address which will be allowed to spend owner's tokens.
    /// @param value The new allowance value.
    /// @param deadline The timestamp which the signature must be submitted by
    ///        to be valid.
    /// @param v Extra ECDSA data which allows public key recovery from
    ///        signature assumed to be 27 or 28.
    /// @param r The r component of the ECDSA signature.
    /// @param s The s component of the ECDSA signature.
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// Getters ///

    /// @notice Gets the ERC20 forwarder's name.
    function name() external view returns (string memory);

    /// @notice Gets the ERC20 forwarder's kind.
    function kind() external pure returns (string memory);

    /// @notice Gets the ERC20 forwarder's version.
    function version() external pure returns (string memory);

    /// @notice Gets a user's nonce for permit.
    /// @param user The user's address.
    /// @return The nonce.
    function nonces(address user) external view returns (uint256);

    /// @notice Gets the target MultiToken of this forwarder.
    /// @return The target MultiToken.
    function token() external view returns (IMultiToken);

    /// @notice Gets the target token ID of this forwarder.
    /// @return The target token ID.
    function tokenId() external view returns (uint256);

    /// @notice The EIP712 domain separator for this contract.
    /// @return The domain separator.
    function domainSeparator() external view returns (bytes32);

    /// @notice The EIP712 typehash for the permit struct used by this contract.
    /// @return The permit typehash.
    // solhint-disable-next-line func-name-mixedcase
    function PERMIT_TYPEHASH() external view returns (bytes32);
}
