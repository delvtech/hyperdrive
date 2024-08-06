// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IAToken as IAToken_ } from "aave/interfaces/IAToken.sol";
import { IPool } from "aave/interfaces/IPool.sol";

interface IAToken is IAToken_ {
    // solhint-disable-next-line func-name-mixedcase
    function POOL() external view returns (IPool);
}
