// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ICornSilo } from "./ICornSilo.sol";
import { IHyperdrive } from "./IHyperdrive.sol";

interface ICornHyperdrive is IHyperdrive {
    /// @notice Returns the Corn Silo contract. This is where the base token
    ///         will be deposited.
    /// @return The Corn Silo contract.
    function cornSilo() external view returns (ICornSilo);
}
