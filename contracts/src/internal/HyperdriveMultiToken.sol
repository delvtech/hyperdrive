// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
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
abstract contract HyperdriveMultiToken is HyperdriveBase {
    /// @notice This modifier checks the caller is the create2 validated ERC20 bridge.
    /// @param tokenID The internal token identifier.
    modifier onlyLinker(uint256 tokenID) {
        // If the caller does not match the address hash, we revert because it is not
        // allowed to access permission-ed methods.
        if (msg.sender != _deriveForwarderAddress(tokenID)) {
            revert IHyperdrive.InvalidERC20Bridge();
        }
        // Execute the following function.
        _;
    }

    /// @dev Transfers several assets from one account to another
    /// @param from the source account.
    /// @param to the destination account.
    /// @param ids The array of token ids of the asset to transfer.
    /// @param values The amount of each token to transfer.
    function _batchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values
    ) internal {
        // Checks for inconsistent addresses.
        if (from == address(0) || to == address(0))
            revert IHyperdrive.RestrictedZeroAddress();

        // Check for inconsistent length.
        if (ids.length != values.length)
            revert IHyperdrive.BatchInputLengthMismatch();

        // Call internal transfer for each asset.
        for (uint256 i = 0; i < ids.length; ) {
            _transferFrom(ids[i], from, to, values[i], msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Performs the actual transfer logic.
    /// @param tokenID The token identifier.
    /// @param from The address who's balance will be reduced.
    /// @param to The address who's balance will be increased.
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
        if (from == address(0) || to == address(0))
            revert IHyperdrive.RestrictedZeroAddress();

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
    /// @param to The address who's balance to increase.
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
    /// @param from The address who's balance to decrease.
    /// @param amount The number of tokens to remove.
    /// @dev Must be used from inheriting contracts.
    function _burn(uint256 tokenID, address from, uint256 amount) internal {
        // Decrement from the source and supply.
        _balanceOf[tokenID][from] -= amount;
        _totalSupply[tokenID] -= amount;

        // Emit an event to track burning.
        emit TransferSingle(msg.sender, from, address(0), tokenID, amount);
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

        // Preform the hash which determines the address of a create2 deployment.
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