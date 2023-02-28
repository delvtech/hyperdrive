// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.10;

import { PoolAddressesProvider } from "@aave/core-v3/contracts/protocol/configuration/PoolAddressesProvider.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

contract MockPoolAddressesProvider is PoolAddressesProvider {
    constructor(
        string memory marketId,
        address owner
    ) PoolAddressesProvider(marketId, owner) {}
}
