// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./IMultiToken.sol";

interface IHyperdrive is IMultiToken {

    function closeLong(
        uint256 _openSharePrice,
        uint32 _maturityTime,
        uint256 _bondAmount
    ) external returns(uint256);

}