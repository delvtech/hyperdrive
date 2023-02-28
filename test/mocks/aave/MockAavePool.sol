// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.10;
import { Pool } from "@aave/core-v3/contracts/protocol/pool/Pool.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

contract MockAavePool is Pool {
    uint16 internal _maxNumberOfReserves = 128;

    function getRevision() internal pure override returns (uint256) {
        return 0x3;
    }

    constructor(IPoolAddressesProvider provider) Pool(provider) {}

    function setMaxNumberOfReserves(uint16 newMaxNumberOfReserves) public {
        _maxNumberOfReserves = newMaxNumberOfReserves;
    }

    function MAX_NUMBER_RESERVES() public view override returns (uint16) {
        return _maxNumberOfReserves;
    }

    function dropReserve(address asset) external override {
        _reservesList[_reserves[asset].id] = address(0);
        delete _reserves[asset];
    }
}
