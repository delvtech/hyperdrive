// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdriveRead } from "./IHyperdriveRead.sol";
import { IRestakeManager, IRenzoOracle } from "./IRenzo.sol";

interface IEzETHHyperdriveRead is IHyperdriveRead {
    /// @notice Gets the Renzo contract used as this pool's yield source.
    /// @return The renzo contract.
    function renzo() external view returns (IRestakeManager);

    /// @notice Gets the RenzoOracle contract.
    /// @return The RenzoOracle contract.
    function renzoOracle() external view returns (IRenzoOracle);
}
