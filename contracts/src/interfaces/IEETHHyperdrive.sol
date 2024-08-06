// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IEETHHyperdrive is IHyperdrive {
    /// @notice Gets the Etherfi liquidity pool.
    /// @return The Etherfi liquidity pool.
    function liquidityPool() external view returns (address);
}
