// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdriveRead } from "../IHyperdriveRead.sol";
import { IRiverV1 } from "./IRiverV1.sol";

interface ILsETHHyperdriveRead is IHyperdriveRead {
    /// @notice Gets the LsETH token contract.
    /// @return The  LsETH token contract.
    function lsEth() external view returns (IRiverV1);
}
