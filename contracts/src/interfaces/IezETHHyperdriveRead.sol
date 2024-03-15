// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdriveRead } from "./IHyperdriveRead.sol";
import { IRestakeManager } from "./IRestakeManager.sol";

interface IEzETHHyperdriveRead is IHyperdriveRead {
    /// @notice Gets the Renzo contract used as this pool's yield source.
    /// @return The renzo contract.
    function renzo() external view returns (IRestakeManager);
}
