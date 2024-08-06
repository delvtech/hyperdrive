// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20Forwarder } from "../interfaces/IERC20Forwarder.sol";
import { IERC20ForwarderFactory } from "../interfaces/IERC20ForwarderFactory.sol";
import { IMultiToken } from "../interfaces/IMultiToken.sol";
import { ERC20_FORWARDER_KIND, VERSION } from "../libraries/Constants.sol";

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
contract ERC20Forwarder is IERC20Forwarder {
    /// @notice The ERC20 forwarder's kind.
    string public constant kind = ERC20_FORWARDER_KIND;

    /// @notice The ERC20 forwarder's version.
    string public constant version = VERSION;

    /// @notice The target token ID that this ERC20 interface forwards to.
    IMultiToken public immutable token;

    /// @notice The target token ID that this ERC20 interface forwards to.
    uint256 public immutable tokenId;

    /// @notice A mapping from a user to their nonce for permit signatures.
    mapping(address user => uint256 nonce) public nonces;

    /// @notice The EIP712 typehash for the permit struct used by this contract
    ///         to validate permit signatures.
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    /// @notice Initializes the ERC20 forwarder.
    /// @dev To give the contract a constant deploy code hash we call back into
    ///      the factory to load info instead of using calldata.
    constructor() {
        // The deployer is the factory.
        IERC20ForwarderFactory factory = IERC20ForwarderFactory(msg.sender);

        // Load the initialization data from the factory.
        (token, tokenId) = factory.getDeployDetails();
    }

    /// @notice Computes the EIP712 domain separator which prevents user signed
    ///         messages for this contract to be replayed in other contracts:
    ///         https://eips.ethereum.org/EIPS/eip-712.
    /// @return The EIP712 domain separator.
    function domainSeparator() public view returns (bytes32) {
        return
            keccak256(
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

    /// @notice Returns the decimals for this ERC20 interface. Hyperdrive's
    ///         sub-tokens always use 18 decimals.
    /// @return The amount of decimals (always 18).
    function decimals() external pure override returns (uint8) {
        return 18;
    }

    /// @notice Returns this token's name. This is the name of the underlying
    ///         MultiToken sub-token.
    /// @return Returns the token's name.
    function name() external view override returns (string memory) {
        return token.name(tokenId);
    }

    /// @notice Returns this token's total supply. This is the total supply
    ///         of the underlying MultiToken sub-token.
    /// @return Returns the total supply of this token.
    function totalSupply() external view override returns (uint256) {
        return token.totalSupply(tokenId);
    }

    /// @notice Returns this token's symbol. This is the symbol of the
    ///         underlying MultiToken sub-token.
    /// @return Returns the token's symbol.
    function symbol() external view override returns (string memory) {
        return token.symbol(tokenId);
    }

    /// @notice Returns a user's token balance. This is the balance of the user
    ///         in the underlying MultiToken sub-token.
    /// @param who The owner of the tokens.
    /// @return Returns the user's balance.
    function balanceOf(address who) external view override returns (uint256) {
        return token.balanceOf(tokenId, who);
    }

    /// @notice Loads the allowance information for an owner spender pair.
    ///         If spender is approved for all tokens in the main contract
    ///         it will return Max(uint256) otherwise it returns the allowance
    ///         the allowance for just this asset.
    /// @param owner The account whose tokens would be spent.
    /// @param spender The account who might be able to spend tokens.
    /// @return The amount of the owner's tokens the spender can spend.
    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        // If the owner is approved for all they can spend an unlimited amount.
        if (token.isApprovedForAll(owner, spender)) {
            return type(uint256).max;
        }
        // Otherwise they can only spend up the their per-token approval for
        // the owner.
        else {
            return token.perTokenApprovals(tokenId, owner, spender);
        }
    }

    /// @notice Sets an approval for just this sub-token for the caller in the
    ///         main token.
    /// @param spender The address which can spend tokens of the caller.
    /// @param amount The amount which the spender is allowed to spend, if it is
    ///        set to uint256.max it is infinite and will not be reduced by
    ///        transfer.
    /// @return True if approval successful, false if not. The contract also
    ///         reverts on failure so only true is possible.
    function approve(address spender, uint256 amount) external returns (bool) {
        // The main token handles the internal approval logic.
        token.setApprovalBridge(tokenId, spender, amount, msg.sender);

        // Emit a ERC20 compliant approval event.
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Forwards a call to transfer from the msg.sender to the recipient.
    /// @param recipient The recipient of the token transfer
    /// @param amount The amount of token to transfer
    /// @return True if transfer successful, false if not. The contract also
    ///         reverts on failed transfer so only true is possible.
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

        // Emits an ERC20 compliant transfer event.
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    /// @notice Forwards a call to transferFrom to move funds from an owner to a
    ///         recipient.
    /// @param source The source of the tokens to be transferred.
    /// @param recipient The recipient of the tokens.
    /// @param amount The amount of tokens to be transferred.
    /// @return Returns true for success false for failure, also reverts on
    ///         fail, so will always return true.
    function transferFrom(
        address source,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        // The token handles the approval logic checking and transfer.
        token.transferFromBridge(
            tokenId,
            source,
            recipient,
            amount,
            msg.sender
        );

        // Emits an ERC20 compliant transfer event.
        emit Transfer(source, recipient, amount);
        return true;
    }

    /// @notice This function allows a caller who is not the owner of an account
    ///         to execute the functionality of 'approve' with the owners
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
    ) external {
        // Require that the signature is not expired.
        if (block.timestamp > deadline) {
            revert IERC20Forwarder.ExpiredDeadline();
        }

        // Require that the owner is not zero.
        if (owner == address(0)) {
            revert IERC20Forwarder.RestrictedZeroAddress();
        }

        // Get the current nonce for the owner and calculate the EIP712 struct.
        uint256 nonce = nonces[owner];
        bytes32 structHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator(),
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

        // Check that the signature is valid.
        address signer = ecrecover(structHash, v, r, s);
        if (signer != owner) {
            revert InvalidSignature();
        }

        // Increment the signature nonce.
        unchecked {
            nonces[owner] = nonce + 1;
        }

        // Set the approval to the new value.
        token.setApprovalBridge(tokenId, spender, value, owner);
        emit Approval(owner, spender, value);
    }
}
