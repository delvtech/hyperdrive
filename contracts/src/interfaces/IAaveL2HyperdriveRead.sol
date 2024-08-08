// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IL2Pool } from "./IAave.sol";
import { IHyperdriveRead } from "./IHyperdriveRead.sol";

interface IAaveL2HyperdriveRead is IHyperdriveRead {
    /// @notice Gets the AaveL2 pool used as this pool's yield source.
    /// @return The AaveL2 pool.
    function vault() external view returns (IL2Pool);
}
