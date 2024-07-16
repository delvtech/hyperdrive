// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IEverlongAdmin } from "contracts/src/interfaces/IEverlongAdmin.sol";

/// @author DELV
/// @title EverlongAdmin
/// @notice Permissioning for Everlong.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EverlongAdmin is IEverlongAdmin {
    /// @inheritdoc IEverlongAdmin
    address public admin;

    constructor() {
        admin = msg.sender;
    }

    /// @dev Ensures that the contract is being called by admin.
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert IEverlongAdmin.Unauthorized();
        }
        _;
    }

    /// @inheritdoc IEverlongAdmin
    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
        emit AdminUpdated(_admin);
    }
}
