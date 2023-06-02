// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

/// @author DELV
/// @title MultiTokenStorage
/// @notice The MultiToken storage contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MultiTokenStorage {
    // The contract which deployed this one
    address internal immutable _factory;

    // The bytecode hash of the contract which forwards purely erc20 calls
    // to this contract
    bytes32 internal immutable _linkerCodeHash;

    // Allows loading of each balance
    mapping(uint256 => mapping(address => uint256)) internal _balanceOf;

    // Allows loading of each total supply
    mapping(uint256 => uint256) internal _totalSupply;

    // Uniform approval for all tokens
    mapping(address => mapping(address => bool)) internal _isApprovedForAll;

    // Additional optional per token approvals
    // Note - non standard for erc1150 but we want to replicate erc20 interface
    mapping(uint256 => mapping(address => mapping(address => uint256)))
        internal _perTokenApprovals;

    // Sub Token Name and Symbol, created by inheriting contracts
    mapping(uint256 => string) internal _name;
    mapping(uint256 => string) internal _symbol;

    // A mapping to track the permitForAll signature nonces
    mapping(address => uint256) internal _nonces;

    /// @notice Initializes the MultiToken's storage.
    /// @param _linkerCodeHash_ The hash of the erc20 linker contract deploy code
    /// @param _factory_ The factory which is used to deploy the linking contracts
    constructor(bytes32 _linkerCodeHash_, address _factory_) {
        // Set the immutables
        _factory = _factory_;
        _linkerCodeHash = _linkerCodeHash_;
    }
}
