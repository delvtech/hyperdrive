// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/// @author DELV
/// @title EtchingVault
/// @dev This is a helper contract that is etched onto a `MockERC4626` vault
///      as one of the intermediate steps in the "etching" process in the Rust
///      debugging tools.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EtchingVault {
    address internal immutable _baseToken;
    uint256 internal immutable _vaultSharePrice;

    constructor(address _baseToken_, uint256 _vaultSharePrice_) {
        _baseToken = _baseToken_;
        _vaultSharePrice = _vaultSharePrice_;
    }

    function asset() external view returns (address) {
        return _baseToken;
    }

    function convertToAssets(uint256) external view returns (uint256) {
        return _vaultSharePrice;
    }
}
