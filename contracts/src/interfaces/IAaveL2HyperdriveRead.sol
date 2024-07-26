// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { L2Pool } from "aave/protocol/pool/L2Pool.sol";
import { IHyperdriveRead } from "./IHyperdriveRead.sol";

interface IAaveL2HyperdriveRead is IHyperdriveRead {
    /// @notice Gets the AaveL2 pool used as this pool's yield source.
    /// @return The AaveL2 pool.
    function vault() external view returns (L2Pool);
}
