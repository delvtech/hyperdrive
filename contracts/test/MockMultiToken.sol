// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { MultiToken } from "../src/MultiToken.sol";
import { IMultiToken } from "../src/interfaces/IMultiToken.sol";
import { ForwarderFactory } from "../src/ForwarderFactory.sol";

interface IMockMultiToken is IMultiToken {
    function __setNameAndSymbol(
        uint256 tokenId,
        string memory __name,
        string memory __symbol
    ) external;

    function __setBalanceOf(
        uint256 _tokenId,
        address _who,
        uint256 _amount
    ) external;

    function __external_transferFrom(
        uint256 tokenID,
        address from,
        address to,
        uint256 amount,
        address caller
    ) external;
}

contract MockMultiToken is MultiToken {
    constructor(
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _factory
    ) MultiToken(_dataProvider, _linkerCodeHash, _factory) {}

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
    ) external {
        _balanceOf[_tokenId][_who] = _amount;
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
