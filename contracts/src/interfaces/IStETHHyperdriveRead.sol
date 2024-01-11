// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdriveRead } from "./IHyperdriveRead.sol";
import { ILido } from "./ILido.sol";

interface IStETHHyperdriveRead is IHyperdriveRead {
    function lido() external view returns (ILido);
}
