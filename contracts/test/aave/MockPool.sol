// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.10;

import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { Pool } from "@aave/core-v3/contracts/protocol/pool/Pool.sol";

contract MockPool is Pool {
    function _onlyPoolConfigurator() internal view override {}

    constructor(IPoolAddressesProvider provider) Pool(provider) {}
}
