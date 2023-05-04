// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

/// @author DELV
/// @title MultiTokenStorage
/// @notice The MultiToken storage contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MultiTokenStorage {
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
}
