// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.10;

import { PoolAddressesProvider } from "@aave/core-v3/contracts/protocol/configuration/PoolAddressesProvider.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { ACLManager } from "@aave/core-v3/contracts/protocol/configuration/ACLManager.sol";

contract MockACLManager {
    function isAssetListingAdmin(address admin) external pure returns (bool) {
        return true;
    }

    function isPoolAdmin(address admin) external pure returns (bool) {
        return true;
    }
}
