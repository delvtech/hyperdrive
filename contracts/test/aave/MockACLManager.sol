// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.10;

import { PoolAddressesProvider } from "@aave/core-v3/contracts/protocol/configuration/PoolAddressesProvider.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { ACLManager } from "@aave/core-v3/contracts/protocol/configuration/ACLManager.sol";

// function _onlyAssetListingOrPoolAdmins() internal view {
//   IACLManager aclManager = IACLManager(_addressesProvider.getACLManager());
//   require(
//     aclManager.isAssetListingAdmin(msg.sender) || aclManager.isPoolAdmin(msg.sender),
//     Errors.CALLER_NOT_ASSET_LISTING_OR_POOL_ADMIN
//   );
// }

contract MockACLManager {
    function isAssetListingAdmin(address admin) external pure returns (bool) {
        return true;
    }

    function isPoolAdmin(address admin) external pure returns (bool) {
        return true;
    }
}
