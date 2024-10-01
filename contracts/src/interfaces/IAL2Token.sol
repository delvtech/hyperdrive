// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IAToken as IAToken_ } from "aave/interfaces/IAToken.sol";
import { IL2Pool } from "./IAave.sol";

interface IAL2Token is IAToken_ {
    // solhint-disable-next-line func-name-mixedcase
    function POOL() external view returns (IL2Pool);
}
