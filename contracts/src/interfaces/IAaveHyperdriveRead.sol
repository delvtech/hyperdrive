// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IPool } from "aave/interfaces/IPool.sol";
import { IHyperdriveRead } from "./IHyperdriveRead.sol";

interface IAaveHyperdriveRead is IHyperdriveRead {
    /// @notice Gets the Aave pool used as this pool's yield source.
    /// @return The Aave pool.
    function vault() external view returns (IPool);
}
