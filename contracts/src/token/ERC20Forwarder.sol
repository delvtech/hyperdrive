// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "../interfaces/IERC20.sol";
import { IForwarderFactory } from "../interfaces/IForwarderFactory.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IMultiToken } from "../interfaces/IMultiToken.sol";

/// @author DELV
/// @title ERC20Forwarder
/// @notice This ERC20Forwarder serves as an ERC20 interface for sub-tokens
///         in a MultiToken contract. This makes it possible for sub-tokens to
///         be used as if they were ERC20 tokens in integrating protocols.
/// @dev This is a permissionless deployed bridge that is linked to a
///      MultiToken contract by a create2 deployment validation. With this in
///      mind, this forwarder MUST be deployed by the right factory in order to
///      function properly.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC20Forwarder is IERC20 {
    // The contract which contains the actual state for this 'ERC20'
    IMultiToken public immutable token;
    // The ID for this contract's 'ERC20' as a sub token of the main token
    uint256 public immutable tokenId;
    // A mapping to track the permit signature nonces
    mapping(address user => uint256 nonce) public nonces;
    // EIP712
    bytes32 public immutable DOMAIN_SEPARATOR; // solhint-disable-line var-name-mixedcase
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    /// @notice Constructs this contract by initializing the immutables
    /// @dev To give the contract a constant deploy code hash we call back
    ///      into the factory to load info instead of using calldata.
    constructor() {
        // The deployer is the factory
        IForwarderFactory factory = IForwarderFactory(msg.sender);
        // We load the data we need to init
        (token, tokenId) = factory.getDeployDetails();

        // Computes the EIP 712 domain separator which prevents user signed messages for
        // this contract to be replayed in other contracts.
        // https://eips.ethereum.org/EIPS/eip-712
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(token.name(tokenId))),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice Returns the decimals for this 'ERC20', we are opinionated
    ///         so we just return 18 in all cases
    /// @return Always 18
    function decimals() external pure override returns (uint8) {
        return (18);
    }

    /// @notice Returns the name of this sub token by calling into the
    ///         main token to load it.
    /// @return Returns the name of this token
    function name() external view override returns (string memory) {
        return (token.name(tokenId));
    }

    /// @notice Returns the totalSupply of the sub token by calling into the
    ///         main token to load it.
    /// @return Returns the totalSupply of this token
    function totalSupply() external view override returns (uint256) {
        return (token.totalSupply(tokenId));
    }

    /// @notice Returns the symbol of this sub token by calling into the
    ///         main token to load it.
    /// @return Returns the symbol of this token
    function symbol() external view override returns (string memory) {
        return (token.symbol(tokenId));
    }

    /// @notice Returns the balance of this sub token through an ERC20 compliant
    ///         interface.
    /// @return The balance of the queried account.
    function balanceOf(address who) external view override returns (uint256) {
        return (token.balanceOf(tokenId, who));
    }

    /// @notice Loads the allowance information for an owner spender pair.
    ///         If spender is approved for all tokens in the main contract
    ///         it will return Max(uint256) otherwise it returns the allowance
    ///         the allowance for just this asset.
    /// @param owner The account who's tokens would be spent
    /// @param spender The account who might be able to spend tokens
    /// @return The amount of the owner's tokens the spender can spend
    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        // If the owner is approved for all they can spend an unlimited amount
        if (token.isApprovedForAll(owner, spender)) {
            return type(uint256).max;
        } else {
            // otherwise they can only spend up the their per token approval for
            // the owner
            return token.perTokenApprovals(tokenId, owner, spender);
        }
    }

    /// @notice Sets an approval for just this sub-token for the caller in the main token
    /// @param spender The address which can spend tokens of the caller
    /// @param amount The amount which the spender is allowed to spend, if it is
    ///               set to uint256.max it is infinite and will not be reduced by transfer.
    /// @return True if approval successful, false if not. The contract also reverts
    ///         on failure so only true is possible.
    function approve(address spender, uint256 amount) external returns (bool) {
        // The main token handles the internal approval logic
        token.setApprovalBridge(tokenId, spender, amount, msg.sender);
        // Emit a ERC20 compliant approval event
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Forwards a call to transfer from the msg.sender to the recipient.
    /// @param recipient The recipient of the token transfer
    /// @param amount The amount of token to transfer
    /// @return True if transfer successful, false if not. The contract also reverts
    ///         on failed transfer so only true is possible.
    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        token.transferFromBridge(
            tokenId,
            msg.sender,
            recipient,
            amount,
            msg.sender
        );
        // Emits an ERC20 compliant transfer event
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    /// @notice Forwards a call to transferFrom to move funds from an owner to a recipient
    /// @param source The source of the tokens to be transferred
    /// @param recipient The recipient of the tokens
    /// @param amount The amount of tokens to be transferred
    /// @return Returns true for success false for failure, also reverts on fail, so will
    ///         always return true.
    function transferFrom(
        address source,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        // The token handles the approval logic checking and transfer
        token.transferFromBridge(
            tokenId,
            source,
            recipient,
            amount,
            msg.sender
        );
        // Emits an ERC20 compliant transfer event
        emit Transfer(source, recipient, amount);
        return true;
    }

    /// @notice This function allows a caller who is not the owner of an account to execute the functionality of 'approve' with the owners signature.
    /// @param owner the owner of the account which is having the new approval set
    /// @param spender the address which will be allowed to spend owner's tokens
    /// @param value the new allowance value
    /// @param deadline the timestamp which the signature must be submitted by to be valid
    /// @param v Extra ECDSA data which allows public key recovery from signature assumed to be 27 or 28
    /// @param r The r component of the ECDSA signature
    /// @param s The s component of the ECDSA signature
    /// @dev The signature for this function follows EIP 712 standard and should be generated with the
    ///      eth_signTypedData JSON RPC call instead of the eth_sign JSON RPC call. If using out of date
    ///      parity signing libraries the v component may need to be adjusted. Also it is very rare but possible
    ///      for v to be other values, those values are not supported.
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Require that the signature is not expired
        if (block.timestamp > deadline) revert IHyperdrive.ExpiredDeadline();
        // Require that the owner is not zero
        if (owner == address(0)) revert IHyperdrive.RestrictedZeroAddress();

        uint256 nonce = nonces[owner];
        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender,
                        value,
                        nonce,
                        deadline
                    )
                )
            )
        );

        // Check that the signature is valid
        address signer = ecrecover(structHash, v, r, s);
        if (signer != owner) revert IHyperdrive.InvalidSignature();

        // Increment the signature nonce
        unchecked {
            nonces[owner] = nonce + 1;
        }
        // Set the approval to the new value
        token.setApprovalBridge(tokenId, spender, value, owner);
        emit Approval(owner, spender, value);
    }
}
