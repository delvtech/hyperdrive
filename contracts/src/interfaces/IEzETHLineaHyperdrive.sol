// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";
import { IXRenzoDeposit } from "./IXRenzoDeposit.sol";

interface IEzETHLineaHyperdrive is IHyperdrive {
    /// @notice Returns the instance's xRenzoDeposit contract. This is the
    ///         contract that provides the vault share price.
    /// @return The instance's xRenzoDeposit contract.
    function xRenzoDeposit() external view returns (IXRenzoDeposit);
}
