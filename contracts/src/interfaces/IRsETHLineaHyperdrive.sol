// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "./IHyperdrive.sol";
import { IRSETHPoolV2 } from "./IRSETHPoolV2.sol";

interface IRsETHLineaHyperdrive is IHyperdrive {
    /// @notice Gets the Kelp DAO deposit contract on Linea. The rsETH/ETH price
    ///         is used as the vault share price.
    /// @return The Kelp DAO deposit contract on Linea.
    function rsETHPool() external view returns (IRSETHPoolV2);
}
