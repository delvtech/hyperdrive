// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.18;

import {AToken} from "./Aave/AToken.sol";

contract DummyATokenA is AToken {
    constructor(address _treasury, address _asset, address _pool)
        AToken(_treasury, _asset, _pool) {}
}
