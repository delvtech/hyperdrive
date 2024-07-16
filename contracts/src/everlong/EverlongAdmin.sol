// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IEverlongAdmin } from "contracts/src/interfaces/IEverlongAdmin.sol";

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
    }
}
