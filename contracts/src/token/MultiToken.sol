// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { DataProvider } from "../DataProvider.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IMultiTokenWrite } from "../interfaces/IMultiTokenWrite.sol";
import { MultiTokenStorage } from "./MultiTokenStorage.sol";

/// @author DELV
/// @title MultiToken
/// @notice A lite version of a semi fungible, which removes some methods and so
///         is not technically a 1155 compliant multi-token semi fungible, but almost
///         follows the standard.
/// @dev We remove on transfer callbacks and safe transfer because of the
///      risk of external calls to untrusted code.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MultiToken is DataProvider, MultiTokenStorage, IMultiTokenWrite {
    // EIP712
    // DOMAIN_SEPARATOR changes based on token name
    bytes32 public immutable DOMAIN_SEPARATOR; // solhint-disable-line var-name-mixedcase
    // PERMIT_TYPEHASH changes based on function inputs
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "PermitForAll(address owner,address spender,bool _approved,uint256 nonce,uint256 deadline)"
        );

    /// @notice Runs the initial deployment code
    /// @param _dataProvider The address of the data provider
    /// @param _linkerCodeHash The hash of the erc20 linker contract deploy code
    /// @param _factory The factory which is used to deploy the linking contracts
    constructor(
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _factory
    ) DataProvider(_dataProvider) MultiTokenStorage(_linkerCodeHash, _factory) {
        // Computes the EIP 712 domain separator which prevents user signed messages for
        // this contract to be replayed in other contracts.
        // https://eips.ethereum.org/EIPS/eip-712
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

    //  Our architecture maintains ERC20 compatibility by allowing the option
    //  of the factory deploying ERC20 compatibility bridges which forward ERC20 calls
    //  to this contract. To maintain trustless deployment they are create2 deployed
    //  with tokenID as salt by the factory, and can be verified by the pre image of
    //  the address.

    /// @notice This modifier checks the caller is the create2 validated ERC20 bridge
    /// @param tokenID The internal token identifier
    modifier onlyLinker(uint256 tokenID) {
        // If the caller does not match the address hash, we revert because it is not
        // allowed to access permission-ed methods.
        if (msg.sender != _deriveForwarderAddress(tokenID)) {
            revert IHyperdrive.InvalidERC20Bridge();
        }
        // Execute the following function
        _;
    }

    /// @notice Derive the ERC20 forwarder address for a provided `tokenId`.
    /// @param tokenId Token Id of the token whose forwarder contract address need to derived.
    /// @return Address of the ERC20 forwarder contract.
    function _deriveForwarderAddress(
        uint256 tokenId
    ) internal view returns (address) {
        // Get the salt which is used by the deploying contract
        bytes32 salt = keccak256(abi.encode(address(this), tokenId));
        // Preform the hash which determines the address of a create2 deployment
        bytes32 addressBytes = keccak256(
            abi.encodePacked(bytes1(0xff), _factory, salt, _linkerCodeHash)
        );
        return address(uint160(uint256(addressBytes)));
    }

    /// @notice Transfers an amount of assets from the source to the destination
    /// @param tokenID The token identifier
    /// @param from The address who's balance will be reduced
    /// @param to The address who's balance will be increased
    /// @param amount The amount of token to move
    function transferFrom(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount
    ) external override {
        // Forward to our internal version
        _transferFrom(tokenID, from, to, amount, msg.sender);
    }

    /// @notice Permission-ed transfer for the bridge to access, only callable by
    ///         the ERC20 linking bridge
    /// @param tokenID The token identifier
    /// @param from The address who's balance will be reduced
    /// @param to The address who's balance will be increased
    /// @param amount The amount of token to move
    /// @param caller The msg.sender from the bridge
    function transferFromBridge(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount,
        address caller
    ) external override onlyLinker(tokenID) {
        // Route to our internal transfer
        _transferFrom(tokenID, from, to, amount, caller);
    }

    /// @notice Preforms the actual transfer logic
    /// @param tokenID The token identifier
    /// @param from The address who's balance will be reduced
    /// @param to The address who's balance will be increased
    /// @param amount The amount of token to move
    /// @param caller The msg.sender either here or in the compatibility link contract
    function _transferFrom(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount,
        address caller
    ) internal {
        // Checks for inconsistent addresses
        if (from == address(0) || to == address(0))
            revert IHyperdrive.RestrictedZeroAddress();

        // If ethereum transaction sender is calling no need for further validation
        if (caller != from) {
            // Or if the transaction sender can access all user assets, no need for
            // more validation
            if (!_isApprovedForAll[from][caller]) {
                // Finally we load the per asset approval
                uint256 approved = _perTokenApprovals[tokenID][from][caller];
                // If it is not an infinite approval
                if (approved != type(uint256).max) {
                    // Then we subtract the amount the caller wants to use
                    // from how much they can use, reverting on underflow.
                    // NOTE - This reverts without message for unapproved callers when
                    //         debugging that's the likely source of any mystery reverts
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

    /// @notice Allows a user to approve an operator to use all of their assets
    /// @param operator The eth address which can access the caller's assets
    /// @param approved True to approve, false to remove approval
    function setApprovalForAll(
        address operator,
        bool approved
    ) external override {
        // set the appropriate state
        _isApprovedForAll[msg.sender][operator] = approved;
        // Emit an event to track approval
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @notice Allows a user to set an approval for an individual asset with specific amount.
    /// @param tokenID The asset to approve the use of
    /// @param operator The address who will be able to use the tokens
    /// @param amount The max tokens the approved person can use, setting to uint256.max
    ///               will cause the value to never decrement [saving gas on transfer]
    function setApproval(
        uint256 tokenID,
        address operator,
        uint256 amount
    ) external override {
        _setApproval(tokenID, operator, amount, msg.sender);
    }

    /// @notice Allows the compatibility linking contract to forward calls to set asset approvals
    /// @param tokenID The asset to approve the use of
    /// @param operator The address who will be able to use the tokens
    /// @param amount The max tokens the approved person can use, setting to uint256.max
    ///               will cause the value to never decrement [saving gas on transfer]
    /// @param caller The eth address which called the linking contract
    function setApprovalBridge(
        uint256 tokenID,
        address operator,
        uint256 amount,
        address caller
    ) external override onlyLinker(tokenID) {
        _setApproval(tokenID, operator, amount, caller);
    }

    /// @notice internal function to change approvals
    /// @param tokenID The asset to approve the use of
    /// @param operator The address who will be able to use the tokens
    /// @param amount The max tokens the approved person can use, setting to uint256.max
    ///               will cause the value to never decrement [saving gas on transfer]
    /// @param caller The eth address which initiated the approval call
    function _setApproval(
        uint256 tokenID,
        address operator,
        uint256 amount,
        address caller
    ) internal {
        _perTokenApprovals[tokenID][caller][operator] = amount;
        // Emit an event to track approval
        emit Approval(caller, operator, amount);
    }

    /// @notice Minting function to create tokens
    /// @param tokenID The asset type to create
    /// @param to The address who's balance to increase
    /// @param amount The number of tokens to create
    /// @dev Must be used from inheriting contracts
    function _mint(
        uint256 tokenID,
        address to,
        uint256 amount
    ) internal virtual {
        _balanceOf[tokenID][to] += amount;
        _totalSupply[tokenID] += amount;
        // Emit an event to track minting
        emit TransferSingle(msg.sender, address(0), to, tokenID, amount);
    }

    /// @notice Burning function to remove tokens
    /// @param tokenID The asset type to remove
    /// @param from The address who's balance to decrease
    /// @param amount The number of tokens to remove
    /// @dev Must be used from inheriting contracts
    function _burn(uint256 tokenID, address from, uint256 amount) internal {
        // Decrement from the source and supply
        _balanceOf[tokenID][from] -= amount;
        _totalSupply[tokenID] -= amount;
        // Emit an event to track burning
        emit TransferSingle(msg.sender, from, address(0), tokenID, amount);
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
        // Checks for inconsistent addresses
        if (from == address(0) || to == address(0))
            revert IHyperdrive.RestrictedZeroAddress();

        // Check for inconsistent length
        if (ids.length != values.length)
            revert IHyperdrive.BatchInputLengthMismatch();

        // Call internal transfer for each asset
        for (uint256 i = 0; i < ids.length; ) {
            _transferFrom(ids[i], from, to, values[i], msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Allows a caller who is not the owner of an account to execute
    ///         the functionality of 'approve' for all assets with the owners signature.
    /// @param owner the owner of the account which is having the new approval set
    /// @param spender the address which will be allowed to spend owner's tokens
    /// @param _approved a boolean of the approval status to set to
    /// @param deadline the timestamp which the signature must be submitted by to be valid
    /// @param v Extra ECDSA data which allows public key recovery from signature assumed to be 27 or 28
    /// @param r The r component of the ECDSA signature
    /// @param s The s component of the ECDSA signature
    /// @dev The signature for this function follows EIP 712 standard and should be generated with the
    ///      eth_signTypedData JSON RPC call instead of the eth_sign JSON RPC call. If using out of date
    ///      parity signing libraries the v component may need to be adjusted. Also it is very rare but possible
    ///      for v to be other values, those values are not supported.
    function permitForAll(
        address owner,
        address spender,
        bool _approved,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Require that the signature is not expired
        if (block.timestamp > deadline) revert IHyperdrive.ExpiredDeadline();
        // Require that the owner is not zero
        if (owner == address(0)) revert IHyperdrive.RestrictedZeroAddress();

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

        // Check that the signature is valid
        address signer = ecrecover(structHash, v, r, s);
        if (signer != owner) revert IHyperdrive.InvalidSignature();

        // Increment the signature nonce
        ++_nonces[owner];
        // set the state
        _isApprovedForAll[owner][spender] = _approved;
        // Emit an event to track approval
        emit ApprovalForAll(owner, spender, _approved);
    }
}
