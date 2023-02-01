// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { IERC1155Mintable } from "contracts/interfaces/IERC1155Mintable.sol";

contract ERC1155Mintable is ERC1155, IERC1155Mintable {
    address public admin;

    event AdminChanged(address indexed newAdmin);

    constructor(string memory _uri) ERC1155(_uri) {
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
    /// @param _id The ID of the token to mint.
    /// @param _amount The amount to send to the target.
    /// @param _data Extra data. This is unused in this contract.
    function mint(
        address _target,
        uint256 _id,
        uint256 _amount,
        bytes memory _data
    ) external onlyAdmin {
        _mint(_target, _id, _amount, _data);
    }

    /// @notice Allows the admin to burn tokens from a specified address.
    /// @param _source The source of the tokens.
    /// @param _id The ID of the token to burn.
    /// @param _amount The amount to burn from the receiver.
    function burn(
        address _source,
        uint256 _id,
        uint256 _amount
    ) external onlyAdmin {
        _burn(_source, _id, _amount);
    }
}
