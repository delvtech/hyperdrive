// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdriveRead } from "./IHyperdriveRead.sol";
import { ILido } from "./ILido.sol";

interface IezETHHyperdriveRead is IHyperdriveRead {
    /// @notice Gets the Lido contract used as this pool's yield source.
    /// @return The Lido contract.
    function lido() external view returns (ILido);
}
