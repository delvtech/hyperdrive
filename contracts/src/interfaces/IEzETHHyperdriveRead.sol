// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdriveRead } from "./IHyperdriveRead.sol";
import { IRestakeManager, IRenzoOracle } from "./IRenzo.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";

interface IEzETHHyperdriveRead is IHyperdriveRead {
    /// @notice Gets the Renzo contract used as this pool's yield source.
    /// @return The renzo contract.
    function renzo() external view returns (IRestakeManager);

    /// @notice Gets the ezETH token contract.
    /// @return The ezETH token contract.
    function ezETH() external view returns (IERC20);

    /// @notice Gets the Renzo Oracle contract.
    /// @return The RenzoOracle contract.
    function renzoOracle() external view returns (IRenzoOracle);
}
