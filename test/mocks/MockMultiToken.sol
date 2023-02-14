// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { BaseTest, TestLib as Lib } from "test/Test.sol";

import { MultiToken } from "contracts/MultiToken.sol";
import { ForwarderFactory } from "contracts/ForwarderFactory.sol";

contract MockMultiToken is MultiToken {
    constructor(
        bytes32 _linkerCodeHash,
        address _factory
    ) MultiToken(_linkerCodeHash, _factory) {}

    function __setNameAndSymbol(
        uint256 tokenId,
        string memory __name,
        string memory __symbol
    ) external {
        _name[tokenId] = __name;
        _symbol[tokenId] = __symbol;
    }

    function __setBalanceOf(
        uint256 _tokenId,
        address _who,
        uint256 _amount
    ) public {
        balanceOf[_tokenId][_who] = _amount;
    }

    function __external_transferFrom(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount,
        address caller
    ) external {
        _transferFrom(tokenID, from, to, amount, caller);
    }
}
