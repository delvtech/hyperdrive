// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

// FIXME: Merge this with HyperdriveStorage
//
/// @author DELV
/// @title MultiTokenStorage
/// @notice The MultiToken storage contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MultiTokenStorage {
    // FIXME: This isn't true.
    //
    // The contract which deployed this one
    address internal immutable _factory;

    // The bytecode hash of the contract which forwards purely erc20 calls
    // to this contract
    bytes32 internal immutable _linkerCodeHash;

    // Allows loading of each balance
    mapping(uint256 tokenId => mapping(address user => uint256 balance))
        internal _balanceOf;

    // Allows loading of each total supply
    mapping(uint256 tokenId => uint256 supply) internal _totalSupply;

    // Uniform approval for all tokens
    mapping(address from => mapping(address caller => bool isApproved))
        internal _isApprovedForAll;

    // Additional optional per token approvals
    //
    // FIXME: Update this comment.
    //
    // Note - non standard for erc1150 but we want to replicate erc20 interface
    mapping(uint256 tokenId => mapping(address from => mapping(address caller => uint256 approved)))
        internal _perTokenApprovals;

    // A mapping to track the permitForAll signature nonces
    mapping(address user => uint256 nonce) internal _nonces;

    /// @notice Initializes the MultiToken's storage.
    /// @param _linkerCodeHash_ The hash of the erc20 linker contract deploy code
    /// @param _factory_ The factory which is used to deploy the linking contracts
    constructor(bytes32 _linkerCodeHash_, address _factory_) {
        // Set the immutables
        _factory = _factory_;
        _linkerCodeHash = _linkerCodeHash_;
    }
}
