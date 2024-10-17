// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { L2Pool } from "aave/protocol/pool/L2Pool.sol";
import { Pool } from "aave/protocol/pool/Pool.sol";
import { IPoolAddressesProvider } from "aave/interfaces/IPoolAddressesProvider.sol";

contract MockL2Pool is L2Pool {
    constructor(
        IPoolAddressesProvider addressesProvider
    ) Pool(addressesProvider) {}

    function initialize(IPoolAddressesProvider provider) public override {
        // does nothing
    }

    function getRevision() internal pure override returns (uint256) {
        return 0;
    }
}
