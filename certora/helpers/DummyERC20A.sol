// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;
import "../../node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";

enum TokenType {
    Native,
    ERC20,
    ERC721,
    ERC1155,
    None
}

// contract DummyERC20A is DummyERC20Impl {}
contract DummyERC20A is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}
}