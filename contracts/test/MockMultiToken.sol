// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IMultiToken } from "../src/interfaces/IMultiToken.sol";
import { ForwarderFactory } from "../src/token/ForwarderFactory.sol";
import { MultiToken } from "../src/token/MultiToken.sol";

interface IMockMultiToken is IMultiToken {
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

    function mint(uint256 tokenID, address to, uint256 amount) external;

    function burn(uint256 tokenID, address from, uint256 amount) external;
}

contract MockMultiToken is MultiToken {
    constructor(
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _factory
    ) MultiToken(address(0), _dataProvider, _linkerCodeHash, _factory) {}

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

    function mint(uint256 tokenID, address to, uint256 amount) external {
        _mint(tokenID, to, amount);
    }

    function burn(uint256 tokenID, address from, uint256 amount) external {
        _burn(tokenID, from, amount);
    }
}
