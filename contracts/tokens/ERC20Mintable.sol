// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Mintable } from "contracts/interfaces/IERC20Mintable.sol";

contract ERC20Mintable is ERC20, IERC20Mintable {
    address public admin;

    event AdminChanged(address indexed newAdmin);

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        admin = msg.sender;
    }

    /// Admin ///

    error NotAdmin();

    /// @dev Ensures that the sender is the admin.
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert NotAdmin();
        }
        _;
    }

    /// @notice Allows the current admin to specify a new admin.
    /// @param _admin The new admin address.
    function changeAdmin(address _admin) external onlyAdmin {
        admin = _admin;
        emit AdminChanged(_admin);
    }

    /// Supply Changes ///

    /// @notice Allows the admin to mint tokens to a specified address.
    /// @param _target The target of the tokens.
    /// @param _amount The amount to send to the target.
    function mint(address _target, uint256 _amount) external onlyAdmin {
        _mint(_target, _amount);
    }

    /// @notice Allows the admin to burn tokens from a specified address.
    /// @param _source The source of the tokens.
    /// @param _amount The amount to burn from the receiver.
    function burn(address _source, uint256 _amount) external onlyAdmin {
        _mint(_source, _amount);
    }
}
